import Foundation
import Combine
import OlafCore

/// Viewer'ın durum sahibi: anlık snapshot + canlı akış birleştirme, seviye/kategori/metin filtresi.
@MainActor
public final class LogViewerModel: ObservableObject {

    /// Toplanan tüm kayıtlar (snapshot + canlı).
    @Published public private(set) var entries: [LogEntry] = []

    /// Gösterim kapsamı.
    public enum Scope: String, CaseIterable, Sendable {
        case session   // bu oturum (bellek ring buffer)
        case history   // diskteki tüm geçmiş (önceki oturumlar dahil)
    }
    @Published public var scope: Scope = .session

    /// Filtreler.
    @Published public var searchText: String = ""
    /// `searchText`'in debounce edilmiş, normalize edilmiş (trim + lowercase) hâli. Her tuş
    /// vuruşunda değil, kullanıcı yazmayı bıraktıktan sonra güncellenir → her keystroke'ta tüm
    /// listeyi taramayız. `filteredEntries` bunu kullanır.
    @Published private var effectiveQuery: String = ""
    /// Gösterilecek seviyeler (çoklu seçim). Boş = hepsi.
    @Published public var enabledLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @Published public var selectedCategories: Set<LogCategory> = []

    /// `true` iken yeni loglar canlı eklenir; `false` (duraklat) iken liste dondurulur.
    @Published public var isFollowing: Bool = true

    private var pendingWhilePaused: [LogEntry] = []
    private var streamTask: Task<Void, Never>?

    /// Canlı akış coalescing tamponu: gelen kayıtlar tek tek `entries`'e (her biri bir
    /// `@Published` yayını → tam SwiftUI diff + `filteredEntries` yeniden hesabı) eklenmek
    /// yerine burada birikir ve kısa aralıkla **toplu** flush edilir. Yoğun loglamada (network
    /// capture) ana thread churn'ü ciddi düşer.
    private var incoming: [LogEntry] = []
    private var flushScheduled = false
    private static let coalesceInterval: UInt64 = 100_000_000  // 100 ms

    /// Geçmiş (disk) yüklenirken `true`.
    @Published public private(set) var isLoading: Bool = false

    public init() {
        // Arama debounce: searchText → (trim+lowercase) → 200ms sessizlik → effectiveQuery.
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .assign(to: &$effectiveQuery)
    }

    deinit { streamTask?.cancel() }

    // MARK: - Yaşam döngüsü

    public func start() {
        reload()
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            for await entry in Olaf.stream() {
                guard let self else { return }
                self.append(entry)
            }
        }
    }

    /// Kapsama göre kayıtları (yeniden) yükler. Hem oturum (bellek) hem geçmiş (disk) modunda
    /// okuma **asenkron** yapılır → UI/ana thread bloke olmaz (çekirdek kuyruk yoğun olsa bile).
    public func reload() {
        pendingWhilePaused.removeAll()
        incoming.removeAll()
        switch scope {
        case .session:
            Task { [weak self] in
                let snapshot = await Olaf.snapshotAsync()
                guard let self else { return }
                self.entries = snapshot
            }
        case .history:
            isLoading = true
            Task { [weak self] in
                let loaded = await Olaf.loadPersistedEntries()
                guard let self else { return }
                self.entries = loaded
                self.isLoading = false
            }
        }
    }

    public func setScope(_ newScope: Scope) {
        guard newScope != scope else { return }
        scope = newScope
        reload()
    }

    private func append(_ entry: LogEntry) {
        incoming.append(entry)
        scheduleFlush()
    }

    /// Birikmiş `incoming` kayıtları kısa bir gecikmeyle **bir kerede** flush eder (coalescing).
    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.coalesceInterval)
            guard let self else { return }
            self.flushScheduled = false
            guard !self.incoming.isEmpty else { return }
            // Duraklatılmışsa kayıtlar "devam et"e dek beklesin (pause semantiği korunur).
            if self.isFollowing {
                self.entries.append(contentsOf: self.incoming)
            } else {
                self.pendingWhilePaused.append(contentsOf: self.incoming)
            }
            self.incoming.removeAll(keepingCapacity: true)
        }
    }

    public func resumeFollowing() {
        isFollowing = true
        if !pendingWhilePaused.isEmpty {
            entries.append(contentsOf: pendingWhilePaused)
            pendingWhilePaused.removeAll()
        }
    }

    // MARK: - Türetilmiş

    /// Mevcut kayıtlarda görülen kategoriler (filtre çubuğu için).
    public var availableCategories: [LogCategory] {
        var seen = Set<LogCategory>()
        var ordered: [LogCategory] = []
        for entry in entries where !seen.contains(entry.category) {
            seen.insert(entry.category)
            ordered.append(entry.category)
        }
        return ordered.sorted { $0.rawValue < $1.rawValue }
    }

    /// Filtre uygulanmış, en yeni en üstte sıralı kayıtlar.
    public var filteredEntries: [LogEntry] {
        let query = effectiveQuery   // debounce edilmiş, zaten trim+lowercase
        return entries.reversed().filter { entry in
            if !enabledLevels.isEmpty, !enabledLevels.contains(entry.level) { return false }
            if !selectedCategories.isEmpty, !selectedCategories.contains(entry.category) {
                return false
            }
            guard !query.isEmpty else { return true }
            if entry.message.lowercased().contains(query) { return true }
            if entry.category.rawValue.lowercased().contains(query) { return true }
            return entry.metadata.contains { key, value in
                key.lowercased().contains(query) || value.lowercased().contains(query)
            }
        }
    }

    // MARK: - Oturum gruplama (geçmiş için)

    /// Bir uygulama oturumunun gruplanmış logları.
    public struct LogSession: Identifiable {
        public let id: String        // sessionID
        public let startDate: Date   // oturumdaki en erken kayıt
        public let entries: [LogEntry]  // en yeni üstte
    }

    /// Geçmişteki kayıtları oturuma göre gruplar — **mevcut oturum hariç** (o "Oturum" sekmesinde).
    /// Oturumlar en yeniden eskiye sıralanır; içleri en yeni üstte.
    public var sessionGroups: [LogSession] {
        let current = Olaf.currentSessionID
        var grouped: [String: [LogEntry]] = [:]
        var order: [String] = []
        for entry in filteredEntries where entry.sessionID != current {
            if grouped[entry.sessionID] == nil { order.append(entry.sessionID) }
            grouped[entry.sessionID, default: []].append(entry)
        }
        return order
            .map { id in
                let items = grouped[id] ?? []
                let start = items.map(\.date).min() ?? .distantPast
                return LogSession(id: id, startDate: start, entries: items)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Aksiyonlar

    public func toggleCategory(_ category: LogCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    public func toggleLevel(_ level: LogLevel) {
        if enabledLevels.contains(level) {
            enabledLevels.remove(level)
        } else {
            enabledLevels.insert(level)
        }
    }

    /// Varsayılan dışı bir filtre uygulanmış mı? (funnel rozetinde gösterilir)
    public var isFiltering: Bool {
        enabledLevels.count != LogLevel.allCases.count || !selectedCategories.isEmpty
    }

    public func resetFilters() {
        enabledLevels = Set(LogLevel.allCases)
        selectedCategories.removeAll()
    }

    public func clear() {
        Olaf.clear()
        entries.removeAll()
        pendingWhilePaused.removeAll()
        incoming.removeAll()
    }

    /// O an **ekranda görünen** (kapsam + seviye/kategori/arama filtreleri uygulanmış) kayıtları
    /// paylaşılabilir bir dosyaya yazar. Hiçbir filtre seçili değilse bu, tüm görünür listeyle
    /// eşittir. Kronolojik (eski → yeni) yazılır; `filteredEntries` en-yeni-üstte sıralı.
    public func exportFileURL() async -> URL? {
        let visible = Array(filteredEntries.reversed())
        return await Olaf.exportFileURL(entries: visible)
    }

    /// Kayıtlı dış araçlar (geçiş butonları).
    public var externalTools: [any ExternalToolBridge] {
        ExternalToolRegistry.shared.all
    }
}

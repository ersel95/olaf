import Foundation
import Combine
import LogFoxCore

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
    /// Gösterilecek seviyeler (çoklu seçim). Boş = hepsi.
    @Published public var enabledLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @Published public var selectedCategories: Set<LogCategory> = []

    /// `true` iken yeni loglar canlı eklenir; `false` (duraklat) iken liste dondurulur.
    @Published public var isFollowing: Bool = true

    private var pendingWhilePaused: [LogEntry] = []
    private var streamTask: Task<Void, Never>?

    /// Geçmiş (disk) yüklenirken `true`.
    @Published public private(set) var isLoading: Bool = false

    public init() {}

    deinit { streamTask?.cancel() }

    // MARK: - Yaşam döngüsü

    public func start() {
        reload()
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            for await entry in LogFox.stream() {
                guard let self else { return }
                self.append(entry)
            }
        }
    }

    /// Kapsama göre kayıtları (yeniden) yükler. Geçmiş modunda disk **asenkron** okunur (UI bloke olmaz).
    public func reload() {
        pendingWhilePaused.removeAll()
        switch scope {
        case .session:
            entries = LogFox.snapshot()
        case .history:
            isLoading = true
            Task { [weak self] in
                let loaded = await LogFox.loadPersistedEntries()
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
        if isFollowing {
            entries.append(entry)
        } else {
            pendingWhilePaused.append(entry)
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        let current = LogFox.currentSessionID
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
        LogFox.clear()
        entries.removeAll()
        pendingWhilePaused.removeAll()
    }

    public func exportFileURL() async -> URL? {
        await LogFox.exportFileURL()
    }

    /// Kayıtlı dış araçlar (örn. Netfox geçiş butonu).
    public var externalTools: [any ExternalToolBridge] {
        ExternalToolRegistry.shared.all
    }
}

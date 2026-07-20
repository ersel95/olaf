import Foundation
import Combine

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

    // MARK: - Geçmişte sayfalama
    //
    // Geçmiş artık tek seferde değil sayfa sayfa yüklenir (en yeniden geriye). Filtre/arama
    // yalnız YÜKLENMİŞ kayıtlarda çalışır; kullanıcı kaydırdıkça (veya butona bastıkça)
    // daha eski sayfalar listenin sonuna eklenir.

    /// Diskte henüz yüklenmemiş daha eski kayıt var mı?
    @Published public private(set) var hasMoreHistory: Bool = false
    /// Daha eski bir sayfa yüklenirken `true` (liste altındaki satır spinner gösterir).
    @Published public private(set) var isLoadingMore: Bool = false
    /// Bir sonraki (daha eski) sayfanın imleci.
    private var historyCursor: String?
    /// Sayfa başına hedeflenen asgari kayıt sayısı.
    private static let historyPageSize = 500

    // MARK: - Türetilmiş (memoize edilmiş) durum
    //
    // Bunlar eskiden computed property idi → her SwiftUI render'ında tüm liste yeniden
    // taranıyordu (büyük Geçmiş'te takılma). Artık yalnız girdiler değişince bir kez
    // hesaplanır ve @Published olarak yayınlanır.

    /// Filtre uygulanmış, en yeni en üstte sıralı kayıtlar.
    @Published public private(set) var filteredEntries: [LogEntry] = []

    /// Geçmişteki kayıtların oturum grupları — **mevcut oturum hariç** (o "Oturum" sekmesinde).
    @Published public private(set) var sessionGroups: [LogSession] = []

    /// Mevcut kayıtlarda görülen kategoriler (filtre çubuğu için).
    @Published public private(set) var availableCategories: [LogCategory] = []

    public init() {
        // Arama debounce: searchText → (trim+lowercase) → 200ms sessizlik → effectiveQuery.
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .assign(to: &$effectiveQuery)

        // Girdilerden türetilen değerler: yalnız girdi değişiminde hesaplanır (render başına değil).
        Publishers.CombineLatest4($entries, $effectiveQuery, $enabledLevels, $selectedCategories)
            .map { entries, query, levels, categories in
                Self.filter(entries: entries, query: query, levels: levels, categories: categories)
            }
            .assign(to: &$filteredEntries)

        $filteredEntries
            .map { Self.groupSessions($0, excluding: Olaf.currentSessionID) }
            .assign(to: &$sessionGroups)

        $entries
            .map { Self.categories(in: $0) }
            .removeDuplicates()
            .assign(to: &$availableCategories)
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
    /// Geçmişte yalnız İLK sayfa yüklenir; gerisi `loadOlderHistory()` ile gelir.
    public func reload() {
        pendingWhilePaused.removeAll()
        incoming.removeAll()
        historyCursor = nil
        hasMoreHistory = false
        isLoadingMore = false
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
                let page = await Olaf.loadPersistedPage(minimumEntries: Self.historyPageSize)
                guard let self else { return }
                self.entries = page.entries
                self.historyCursor = page.nextCursor
                self.hasMoreHistory = page.nextCursor != nil
                self.isLoading = false
            }
        }
    }

    /// Geçmişte bir sonraki (daha eski) sayfayı yükler ve listenin sonuna ekler.
    /// İdempotent: yükleme sürerken veya imleç yokken çağrılar no-op'tur.
    public func loadOlderHistory() {
        guard scope == .history, !isLoading, !isLoadingMore, let cursor = historyCursor else { return }
        isLoadingMore = true
        Task { [weak self] in
            let page = await Olaf.loadPersistedPage(before: cursor, minimumEntries: Self.historyPageSize)
            guard let self else { return }
            // Sayfa bu arada reload ile sıfırlandıysa (kapsam değişimi vb.) sonucu uygulama.
            guard self.scope == .history, self.historyCursor == cursor else {
                self.isLoadingMore = false
                return
            }
            // `entries` eskiden yeniye tutulur; daha eski sayfa BAŞA eklenir.
            self.entries.insert(contentsOf: page.entries, at: 0)
            self.historyCursor = page.nextCursor
            self.hasMoreHistory = page.nextCursor != nil
            self.isLoadingMore = false
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
            // Geçmiş kapsamında canlı kayıtlar listeye karıştırılmaz (mevcut oturum orada zaten
            // gösterilmez); Oturum'a dönüşte reload() güncel snapshot'ı alır — kayıp olmaz.
            if self.scope == .history {
                self.incoming.removeAll(keepingCapacity: true)
                return
            }
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

    // MARK: - Türetme mantığı (saf fonksiyonlar → test edilebilir)

    /// Bir uygulama oturumunun gruplanmış logları.
    public struct LogSession: Identifiable, Sendable {
        public let id: String        // sessionID
        public let startDate: Date   // oturumdaki en erken kayıt
        public let entries: [LogEntry]  // en yeni üstte
    }

    /// Seviye/kategori/arama filtresi — en yeni en üstte.
    nonisolated static func filter(
        entries: [LogEntry],
        query: String,   // zaten trim+lowercase (debounce pipeline'ından)
        levels: Set<LogLevel>,
        categories: Set<LogCategory>
    ) -> [LogEntry] {
        entries.reversed().filter { entry in
            if !levels.isEmpty, !levels.contains(entry.level) { return false }
            if !categories.isEmpty, !categories.contains(entry.category) { return false }
            guard !query.isEmpty else { return true }
            if entry.message.lowercased().contains(query) { return true }
            if entry.category.rawValue.lowercased().contains(query) { return true }
            return entry.metadata.contains { key, value in
                key.lowercased().contains(query) || value.lowercased().contains(query)
            }
        }
    }

    /// Kayıtları oturuma göre gruplar; `excluding` (mevcut oturum) atlanır.
    /// Oturumlar en yeniden eskiye sıralanır; içleri en yeni üstte.
    nonisolated static func groupSessions(_ entries: [LogEntry], excluding current: String) -> [LogSession] {
        var grouped: [String: [LogEntry]] = [:]
        var order: [String] = []
        for entry in entries where entry.sessionID != current {
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

    /// Kayıtlarda görülen kategoriler (ada göre sıralı, tekrarsız).
    nonisolated static func categories(in entries: [LogEntry]) -> [LogCategory] {
        var seen = Set<LogCategory>()
        var ordered: [LogCategory] = []
        for entry in entries where !seen.contains(entry.category) {
            seen.insert(entry.category)
            ordered.append(entry.category)
        }
        return ordered.sorted { $0.rawValue < $1.rawValue }
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

    /// Görünen kayıtları **ham NDJSON** olarak dışa aktarır (jq/backend analizi için).
    public func exportNDJSONFileURL() async -> URL? {
        let visible = Array(filteredEntries.reversed())
        return await Olaf.exportNDJSONFileURL(entries: visible)
    }

    /// Görünen **network** kayıtlarını HAR 1.2 dosyasına yazar (Charles/Proxyman/DevTools açar).
    public func exportHARFileURL() async -> URL? {
        let visible = Array(filteredEntries.reversed())
        return await Task.detached(priority: .utility) {
            guard let text = HARExporter.harDocument(from: visible) else { return nil }
            return LogExportFile.write(text, fileExtension: "har")
        }.value
    }

    /// Görünen **network** kayıtlarını Postman Collection v2.1 dosyasına yazar
    /// (aynı method+URL bir kez; Postman → Import ile yeniden çalıştırılabilir).
    public func exportPostmanFileURL() async -> URL? {
        let visible = Array(filteredEntries.reversed())
        return await Task.detached(priority: .utility) {
            guard let text = PostmanExporter.collection(from: visible) else { return nil }
            return LogExportFile.write(text, fileExtension: "postman_collection.json")
        }.value
    }

    /// Kayıtlı dış araçlar (geçiş butonları).
    public var externalTools: [any ExternalToolBridge] {
        ExternalToolRegistry.shared.all
    }
}

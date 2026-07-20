import Foundation

/// Olaf'un genel (public) cephesi. Tek satır kurulum + ergonomik log API'si.
///
/// ```swift
/// Olaf.start(.default)
/// Olaf.info("Login başarılı", category: .auth, metadata: ["method": "biometric"])
/// Olaf.error("Transfer reddedildi", category: .payment, metadata: ["code": code])
/// ```
public enum Olaf {

    /// Süreç boyunca tek örnek. `start(_:)` çağrılana dek pasiftir.
    /// (internal: OSLog importer gibi modül-içi uzantılar store'a buradan erişir.)
    static let runtime = OlafRuntime()

    // MARK: - Kurulum

    /// Olaf'u başlatır. İdempotenttir — birden çok çağrı ilkini korur.
    public static func start(_ configuration: OlafConfiguration = .default) {
        runtime.start(with: configuration)
    }

    /// Çalışma anında tamamen aç/kapa (kill switch). Kapalıyken hiçbir log işlenmez.
    public static var isEnabled: Bool {
        get { runtime.isEnabled }
        set { runtime.isEnabled = newValue }
    }

    /// Olaf başlatıldı mı?
    public static var isStarted: Bool { runtime.isStarted }

    /// Toplama eşiği: bu seviyenin altındaki loglar hiç işlenmez (mesaj compute bile edilmez).
    /// `start` config'inden gelir; çalışma anında değiştirilebilir (örn. gürültüyü kısmak için
    /// "yalnız warning+ topla"). Kalıcı değildir — süreç ömrüyle sınırlıdır.
    public static var minimumLevel: LogLevel {
        get { runtime.minimumLevel }
        set { runtime.minimumLevel = newValue }
    }

    /// Mevcut uygulama oturumunun kimliği (her `start()` yeni üretir). Geçmişte oturum gruplama için.
    public static var currentSessionID: String { runtime.currentSessionID }

    // MARK: - Log API

    public static func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        category: LogCategory = .general,
        metadata: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        switch runtime.target(for: level) {
        case .drop:
            return
        case .store(let store):
            store.ingest(
                date: Date(),
                level: level,
                category: category,
                rawMessage: message(),
                rawMetadata: metadata,
                file: file,
                line: line,
                function: function,
                thread: OlafRuntime.currentThreadLabel()
            )
        case .buffer:
            // start() öncesi → tamponla (start'ta flush edilir, erken loglar kaybolmaz).
            runtime.buffer(
                date: Date(),
                level: level,
                category: category,
                rawMessage: message(),
                rawMetadata: metadata,
                file: file,
                line: line,
                function: function,
                thread: OlafRuntime.currentThreadLabel()
            )
        }
    }

    public static func trace(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.trace, message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public static func debug(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.debug, message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public static func info(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.info, message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public static func notice(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.notice, message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public static func warning(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.warning, message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public static func error(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.error, message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public static func critical(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        log(.critical, message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    /// Bir `Error` nesnesini doğrudan loglar. Mesaj `localizedDescription`, tip bilgisi metadata'ya eklenir.
    public static func error(_ error: Error, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        var enriched = metadata
        enriched["errorType"] = String(describing: type(of: error))
        enriched["errorDetail"] = String(describing: error)
        log(.error, error.localizedDescription, category: category, metadata: enriched, file: file, line: line, function: function)
    }

    // MARK: - Navigation tracking

    /// Bir ekran geçişini `.navigation` kategorisinde loglar. Generic, string-tabanlı API —
    /// SDK herhangi bir navigasyon kütüphanesine (Coordinator vb.) **bağımlı değildir**; host
    /// kendi navigasyon hook'undan bu metodu çağırır.
    ///
    /// ```swift
    /// // Coordinator observer adapter'ından (host tarafı):
    /// Olaf.trackScreen("dashboard", kind: "push")
    /// Olaf.trackScreen("paymentSheet", kind: "sheet")
    /// ```
    ///
    /// - Parameters:
    ///   - name: Ekran kimliği / adı (örn. `CoordinatorEntryPoint.id`). Mesaj olarak loglanır.
    ///   - kind: Geçiş türü ("push", "sheet", "popup", "root", "dismiss" …). Metadata'ya yazılır.
    public static func trackScreen(
        _ name: String,
        kind: String = "push",
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        log(
            .info,
            name,
            category: .navigation,
            metadata: ["screen": name, "kind": kind],
            file: file,
            line: line,
            function: function
        )
    }

    // MARK: - Okuma & yönetim (viewer bu API üzerinden besler)

    /// Mevcut tampondaki (bu oturum, bellek) kayıtların anlık kopyası (eskiden yeniye).
    public static func snapshot() -> [LogEntry] {
        runtime.store?.snapshot() ?? []
    }

    /// `snapshot()`'ın bloke etmeyen sürümü. Çekirdek kuyruk yoğun yazma burst'ü işlerken
    /// ana thread'i `queue.sync` ile bekletmemek için viewer bunu kullanır.
    public static func snapshotAsync() async -> [LogEntry] {
        guard let store = runtime.store else { return [] }
        return await store.snapshotAsync()
    }

    /// Diskteki tüm kayıtlar — **önceki oturumlar dahil** (ring buffer kapasitesinden bağımsız).
    /// Ağır dosya I/O arka planda yapılır; çağıran (ör. ana thread) bloke olmaz.
    /// Büyük geçmişlerde tamamını belleğe almamak için `loadPersistedPage(before:minimumEntries:)`
    /// ile sayfalı okuma tercih edin (viewer bunu kullanır).
    public static func loadPersistedEntries() async -> [LogEntry] {
        guard let store = runtime.store else { return [] }
        return await store.loadPersisted()
    }

    /// Diskteki geçmişi **sayfalı** okur — en yeniden geriye doğru. İlk sayfa için `before: nil`;
    /// sonraki (daha eski) sayfa için önceki sayfanın `nextCursor`'ını verin. `nextCursor == nil`
    /// geçmişin sonu demektir. Sayfa, en az `minimumEntries` kayıt içerene dek bütün NDJSON
    /// dosyalarından oluşur (dosyalar bölünmez).
    public static func loadPersistedPage(
        before cursor: String? = nil,
        minimumEntries: Int = 500
    ) async -> PersistedLogPage {
        guard let store = runtime.store else { return PersistedLogPage(entries: [], nextCursor: nil) }
        return await store.loadPersistedPage(before: cursor, minimumEntries: minimumEntries)
    }

    /// Yeni kayıtları canlı yayınlayan akış.
    public static func stream() -> AsyncStream<LogEntry> {
        runtime.store?.makeStream() ?? AsyncStream { $0.finish() }
    }

    /// Tüm logları (bellek + disk) temizler.
    public static func clear() {
        runtime.store?.clear()
    }

    /// Tüm logları tek dosyada birleştirip paylaşılabilir bir URL döndürür (asenkron, bloke etmez).
    public static func exportFileURL() async -> URL? {
        guard let store = runtime.store else { return nil }
        return await store.exportFileURL()
    }

    /// Verilen kayıtları paylaşılabilir bir dosyaya yazar (asenkron, bloke etmez). Viewer, o an
    /// **filtreli** görünen listeyi paylaşmak için bunu kullanır; kayıt seçimi çağırana aittir.
    public static func exportFileURL(entries: [LogEntry]) async -> URL? {
        guard let store = runtime.store else { return nil }
        return await store.exportFileURL(entries: entries)
    }

    /// Verilen kayıtları **ham NDJSON** (.ndjson — satır başına bir JSON `LogEntry`) dosyasına
    /// yazar. Disk formatıyla aynı şema: jq/backend analizi/başka araçlara kayıpsız beslenebilir.
    public static func exportNDJSONFileURL(entries: [LogEntry]) async -> URL? {
        guard let store = runtime.store else { return nil }
        return await store.exportNDJSONFileURL(entries: entries)
    }
}

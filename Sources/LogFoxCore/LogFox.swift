import Foundation

/// LogFox'un genel (public) cephesi. Tek satır kurulum + ergonomik log API'si.
///
/// ```swift
/// LogFox.start(.bankingDefault)
/// LogFox.info("Login başarılı", category: .auth, metadata: ["method": "biometric"])
/// LogFox.error("Transfer reddedildi", category: .payment, metadata: ["code": code])
/// ```
public enum LogFox {

    /// Süreç boyunca tek örnek. `start(_:)` çağrılana dek pasiftir.
    private static let runtime = LogFoxRuntime()

    // MARK: - Kurulum

    /// LogFox'u başlatır. İdempotenttir — birden çok çağrı ilkini korur.
    public static func start(_ configuration: LogFoxConfiguration = .default) {
        runtime.start(with: configuration)
    }

    /// Çalışma anında tamamen aç/kapa (kill switch). Kapalıyken hiçbir log işlenmez.
    public static var isEnabled: Bool {
        get { runtime.isEnabled }
        set { runtime.isEnabled = newValue }
    }

    /// LogFox başlatıldı mı?
    public static var isStarted: Bool { runtime.isStarted }

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
        guard let store = runtime.activeStore(for: level) else { return }
        store.ingest(
            date: Date(),
            level: level,
            category: category,
            rawMessage: message(),
            rawMetadata: metadata,
            file: file,
            line: line,
            function: function,
            thread: LogFoxRuntime.currentThreadLabel()
        )
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

    // MARK: - Okuma & yönetim (viewer bu API üzerinden besler)

    /// Mevcut tampondaki (bu oturum, bellek) kayıtların anlık kopyası (eskiden yeniye).
    public static func snapshot() -> [LogEntry] {
        runtime.store?.snapshot() ?? []
    }

    /// Diskteki tüm kayıtlar — **önceki oturumlar dahil** (ring buffer kapasitesinden bağımsız).
    /// TestFlight teşhisi için "uygulama yeniden başlamadan önce ne oldu" sorusunu cevaplar.
    public static func loadPersistedEntries() -> [LogEntry] {
        runtime.store?.loadPersisted() ?? []
    }

    /// Yeni kayıtları canlı yayınlayan akış.
    public static func stream() -> AsyncStream<LogEntry> {
        runtime.store?.makeStream() ?? AsyncStream { $0.finish() }
    }

    /// Tüm logları (bellek + disk) temizler.
    public static func clear() {
        runtime.store?.clear()
    }

    /// Tüm logları tek dosyada birleştirip paylaşılabilir bir URL döndürür.
    public static func exportFileURL() -> URL? {
        runtime.store?.exportFileURL()
    }
}

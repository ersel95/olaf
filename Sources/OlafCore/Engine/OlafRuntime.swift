import Foundation

/// `Olaf` cephesinin arkasındaki durum sahibi. Store yaşam döngüsünü, kill switch'i ve
/// seviye eşiğini kilitle korur. `@unchecked Sendable` — tüm değişken durum `lock` arkasında.
final class OlafRuntime: @unchecked Sendable {

    private let lock = NSLock()
    private var _store: LogStore?
    private var _minimumLevel: LogLevel = .debug
    private var _enabled = true
    private var _sessionID = ""

    /// `start()` çağrılmadan ÖNCE atılan loglar buraya tamponlanır ve start'ta flush edilir.
    /// (Uygulama açılışındaki erken loglar — örn. splash — kaybolmasın.)
    private var _pending: [PendingLog] = []
    private let maxPending = 1000

    private struct PendingLog {
        let date: Date
        let level: LogLevel
        let category: LogCategory
        let rawMessage: String
        let rawMetadata: [String: String]
        let file: String
        let line: Int
        let function: String
        let thread: String
    }

    /// Bir log çağrısının nereye gideceği.
    enum LogTarget {
        case store(LogStore)   // başlatıldı + seviye eşiğini geçti → doğrudan yaz
        case buffer            // henüz başlatılmadı → tamponla (start'ta flush)
        case drop              // kapalı veya seviye eşiğin altında → at
    }

    // MARK: - Yaşam döngüsü

    /// İdempotent başlatma. İlk çağrı kazanır.
    func start(with configuration: OlafConfiguration) {
        lock.lock(); defer { lock.unlock() }
        guard _store == nil else { return }

        _sessionID = Self.makeSessionID()

        let persistence: FilePersistence?
        if configuration.persistsToDisk {
            persistence = FilePersistence(
                directory: Self.defaultLogDirectory(),
                maxFileSize: configuration.maxFileSize,
                maxFileCount: configuration.maxFileCount
            )
        } else {
            persistence = nil
        }

        let mirror = configuration.mirrorsToOSLog
            ? OSLogMirror(subsystem: configuration.subsystem)
            : nil

        _store = LogStore(
            capacity: configuration.inMemoryCapacity,
            persistence: persistence,
            exportFormatter: configuration.exportFormatter,
            osLogMirror: mirror,
            sessionID: _sessionID
        )
        _minimumLevel = configuration.minimumLevel

        // start öncesi tamponlanan logları (seviye eşiğine göre) flush et.
        if let store = _store, !_pending.isEmpty {
            for pending in _pending where pending.level >= _minimumLevel {
                store.ingest(
                    date: pending.date,
                    level: pending.level,
                    category: pending.category,
                    rawMessage: pending.rawMessage,
                    rawMetadata: pending.rawMetadata,
                    file: pending.file,
                    line: pending.line,
                    function: pending.function,
                    thread: pending.thread
                )
            }
            _pending.removeAll()
        }
    }

    // MARK: - Erişim

    var store: LogStore? {
        lock.lock(); defer { lock.unlock() }
        return _store
    }

    var isStarted: Bool {
        lock.lock(); defer { lock.unlock() }
        return _store != nil
    }

    /// Mevcut oturum kimliği (`start()` sonrası dolar; öncesinde boş).
    var currentSessionID: String {
        lock.lock(); defer { lock.unlock() }
        return _sessionID
    }

    var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _enabled }
        set { lock.lock(); _enabled = newValue; lock.unlock() }
    }

    /// Bir log çağrısının hedefini belirler (mesaj yalnız `.drop` değilse compute edilir).
    func target(for level: LogLevel) -> LogTarget {
        lock.lock(); defer { lock.unlock() }
        guard _enabled else { return .drop }
        if let store = _store {
            return level >= _minimumLevel ? .store(store) : .drop
        }
        return .buffer   // henüz başlatılmadı → tamponla
    }

    /// Start öncesi log'u tamponlar (start bu arada çağrıldıysa doğrudan store'a yazar).
    func buffer(
        date: Date,
        level: LogLevel,
        category: LogCategory,
        rawMessage: String,
        rawMetadata: [String: String],
        file: String,
        line: Int,
        function: String,
        thread: String
    ) {
        lock.lock(); defer { lock.unlock() }
        if let store = _store {
            store.ingest(date: date, level: level, category: category, rawMessage: rawMessage, rawMetadata: rawMetadata, file: file, line: line, function: function, thread: thread)
            return
        }
        _pending.append(PendingLog(date: date, level: level, category: category, rawMessage: rawMessage, rawMetadata: rawMetadata, file: file, line: line, function: function, thread: thread))
        if _pending.count > maxPending {
            _pending.removeFirst(_pending.count - maxPending)
        }
    }

    // MARK: - Yardımcılar

    /// Oturum kimliği: zaman damgası tabanlı sıralanabilir bir önek + kısa rastgele kuyruk.
    static func makeSessionID() -> String {
        "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))"
    }

    static func defaultLogDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Olaf", isDirectory: true)
    }

    /// Çağıran thread'in okunur etiketi: "main" / thread adı / dispatch queue label.
    static func currentThreadLabel() -> String {
        if Thread.isMainThread { return "main" }
        if let name = Thread.current.name, !name.isEmpty { return name }
        let label = String(cString: __dispatch_queue_get_label(nil))
        return label.isEmpty ? "background" : label
    }
}

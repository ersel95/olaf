import Foundation

/// The state owner behind the `Olaf` facade. Guards the store's lifecycle, the kill switch, and
/// the level threshold with a lock. `@unchecked Sendable` — all mutable state sits behind `lock`.
final class OlafRuntime: @unchecked Sendable {

    private let lock = NSLock()
    private var _store: LogStore?
    private var _minimumLevel: LogLevel = .debug
    private var _enabled = true
    private var _sessionID = ""

    /// Logs emitted BEFORE `start()` is called are buffered here and flushed on start.
    /// (So early logs during app launch — e.g. splash — aren't lost.)
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

    /// Where a log call should go.
    enum LogTarget {
        case store(LogStore)   // started + passed the level threshold → write directly
        case buffer            // not yet started → buffer (flushed on start)
        case drop              // disabled or below the level threshold → discard
    }

    // MARK: - Lifecycle

    /// Idempotent start. The first call wins.
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

        // Flush logs buffered before start (according to the level threshold).
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

    // MARK: - Access

    var store: LogStore? {
        lock.lock(); defer { lock.unlock() }
        return _store
    }

    var isStarted: Bool {
        lock.lock(); defer { lock.unlock() }
        return _store != nil
    }

    /// Current session identifier (populated after `start()`; empty before that).
    var currentSessionID: String {
        lock.lock(); defer { lock.unlock() }
        return _sessionID
    }

    var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _enabled }
        set { lock.lock(); _enabled = newValue; lock.unlock() }
    }

    /// Collection threshold. Comes from the `start` config; can be changed at runtime
    /// (e.g. the "Collection threshold" setting in the viewer). Not persistent — scoped to the process lifetime.
    var minimumLevel: LogLevel {
        get { lock.lock(); defer { lock.unlock() }; return _minimumLevel }
        set { lock.lock(); _minimumLevel = newValue; lock.unlock() }
    }

    /// Determines the target of a log call (the message is only computed if not `.drop`).
    func target(for level: LogLevel) -> LogTarget {
        lock.lock(); defer { lock.unlock() }
        guard _enabled else { return .drop }
        if let store = _store {
            return level >= _minimumLevel ? .store(store) : .drop
        }
        return .buffer   // not yet started → buffer
    }

    /// Buffers a pre-start log (writes directly to the store if start was called in the meantime).
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

    // MARK: - Helpers

    /// Session identifier: a sortable timestamp-based prefix + a short random suffix.
    static func makeSessionID() -> String {
        "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))"
    }

    static func defaultLogDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Olaf", isDirectory: true)
    }

    /// A readable label for the calling thread: "main" / thread name / dispatch queue label.
    static func currentThreadLabel() -> String {
        if Thread.isMainThread { return "main" }
        if let name = Thread.current.name, !name.isEmpty { return name }
        let label = String(cString: __dispatch_queue_get_label(nil))
        return label.isEmpty ? "background" : label
    }
}

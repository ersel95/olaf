import Foundation

/// `LogFox` cephesinin arkasındaki durum sahibi. Store yaşam döngüsünü, kill switch'i ve
/// seviye eşiğini kilitle korur. `@unchecked Sendable` — tüm değişken durum `lock` arkasında.
final class LogFoxRuntime: @unchecked Sendable {

    private let lock = NSLock()
    private var _store: LogStore?
    private var _minimumLevel: LogLevel = .debug
    private var _enabled = true

    // MARK: - Yaşam döngüsü

    /// İdempotent başlatma. İlk çağrı kazanır.
    func start(with configuration: LogFoxConfiguration) {
        lock.lock(); defer { lock.unlock() }
        guard _store == nil else { return }

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
            redactor: configuration.redactor,
            persistence: persistence,
            exportFormatter: configuration.exportFormatter,
            osLogMirror: mirror
        )
        _minimumLevel = configuration.minimumLevel
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

    var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _enabled }
        set { lock.lock(); _enabled = newValue; lock.unlock() }
    }

    /// Hızlı kapı: log işlenecekse aktif store'u döndürür, aksi halde `nil`.
    /// (kill switch kapalı veya seviye eşiğin altındaysa mesaj compute edilmez.)
    func activeStore(for level: LogLevel) -> LogStore? {
        lock.lock(); defer { lock.unlock() }
        guard _enabled, let store = _store, level >= _minimumLevel else { return nil }
        return store
    }

    // MARK: - Yardımcılar

    static func defaultLogDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LogFox", isDirectory: true)
    }

    /// Çağıran thread'in okunur etiketi: "main" / thread adı / dispatch queue label.
    static func currentThreadLabel() -> String {
        if Thread.isMainThread { return "main" }
        if let name = Thread.current.name, !name.isEmpty { return name }
        let label = String(cString: __dispatch_queue_get_label(nil))
        return label.isEmpty ? "background" : label
    }
}

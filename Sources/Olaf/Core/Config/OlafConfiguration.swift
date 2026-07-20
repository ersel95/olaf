import Foundation

/// Configuration for the Olaf core. Supplied once via `Olaf.start(_:)`.
public struct OlafConfiguration: Sendable {

    /// Logs below this level are completely ignored (the message isn't even computed).
    public var minimumLevel: LogLevel

    /// In-memory ring buffer capacity (the newest N entries are kept in RAM).
    public var inMemoryCapacity: Int

    /// Should logs also be written to disk? (for access after the app restarts)
    public var persistsToDisk: Bool

    /// The active log file is rotated once it exceeds this size (bytes).
    public var maxFileSize: Int

    /// Maximum number of files kept on disk (oldest are deleted).
    public var maxFileCount: Int

    /// **Human-readable** format used during export (.log sharing). On-disk storage is always
    /// NDJSON (for round-trip readability); this formatter only produces the shared text.
    public var exportFormatter: any LogFormatter

    /// OSLog (`os.Logger`) bridge — should logs also show up in Console.app?
    public var mirrorsToOSLog: Bool

    /// Subsystem for the OSLog bridge (typically the bundle id).
    public var subsystem: String

    public init(
        minimumLevel: LogLevel = .trace,   // default on: all levels are captured
        inMemoryCapacity: Int = 2000,
        persistsToDisk: Bool = true,
        maxFileSize: Int = 1_048_576,        // 1 MB
        maxFileCount: Int = 5,
        exportFormatter: any LogFormatter = PlainTextFormatter(),
        mirrorsToOSLog: Bool = true,
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.olaf"
    ) {
        self.minimumLevel = minimumLevel
        self.inMemoryCapacity = max(1, inMemoryCapacity)
        self.persistsToDisk = persistsToDisk
        self.maxFileSize = max(4096, maxFileSize)
        self.maxFileCount = max(1, maxFileCount)
        self.exportFormatter = exportFormatter
        self.mirrorsToOSLog = mirrorsToOSLog
        self.subsystem = subsystem
    }

    /// General-purpose default.
    public static let `default` = OlafConfiguration()
}

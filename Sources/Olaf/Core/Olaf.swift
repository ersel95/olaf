import Foundation

/// Olaf's public facade. One-line setup + an ergonomic logging API.
///
/// ```swift
/// Olaf.start(.default)
/// Olaf.info("Login successful", category: .auth, metadata: ["method": "biometric"])
/// Olaf.error("Transfer declined", category: .payment, metadata: ["code": code])
/// ```
public enum Olaf {

    /// Process-wide singleton. Inactive until `start(_:)` is called.
    /// (internal: in-module extensions like the OSLog importer access the store through this.)
    static let runtime = OlafRuntime()

    // MARK: - Setup

    /// Starts Olaf. Idempotent — multiple calls keep the first one.
    public static func start(_ configuration: OlafConfiguration = .default) {
        runtime.start(with: configuration)
    }

    /// Full runtime on/off switch (kill switch). No logs are processed while disabled.
    public static var isEnabled: Bool {
        get { runtime.isEnabled }
        set { runtime.isEnabled = newValue }
    }

    /// Has Olaf been started?
    public static var isStarted: Bool { runtime.isStarted }

    /// Collection threshold: logs below this level are never processed (the message isn't even
    /// computed). Comes from the `start` config; can be changed at runtime (e.g. to cut down
    /// noise by "only collecting warning+"). Not persistent — scoped to the process lifetime.
    public static var minimumLevel: LogLevel {
        get { runtime.minimumLevel }
        set { runtime.minimumLevel = newValue }
    }

    /// Identifier of the current app session (each `start()` generates a new one). Used for grouping sessions in history.
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
            // Before start() → buffer (flushed on start, so early logs aren't lost).
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

    /// Logs an `Error` object directly. The message is `localizedDescription`; type info is added to metadata.
    public static func error(_ error: Error, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        var enriched = metadata
        enriched["errorType"] = String(describing: type(of: error))
        enriched["errorDetail"] = String(describing: error)
        log(.error, error.localizedDescription, category: category, metadata: enriched, file: file, line: line, function: function)
    }

    // MARK: - Navigation tracking

    /// Logs a screen transition under the `.navigation` category. A generic, string-based API —
    /// the SDK is **not dependent** on any navigation library (Coordinator, etc.); the host
    /// calls this method from its own navigation hook.
    ///
    /// ```swift
    /// // From a Coordinator observer adapter (host side):
    /// Olaf.trackScreen("dashboard", kind: "push")
    /// Olaf.trackScreen("paymentSheet", kind: "sheet")
    /// ```
    ///
    /// - Parameters:
    ///   - name: Screen identifier / name (e.g. `CoordinatorEntryPoint.id`). Logged as the message.
    ///   - kind: Transition type ("push", "sheet", "popup", "root", "dismiss" …). Written to metadata.
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

    // MARK: - Reading & management (the viewer is fed through this API)

    /// An instant copy of the entries currently in the buffer (this session, in memory), oldest to newest.
    public static func snapshot() -> [LogEntry] {
        runtime.store?.snapshot() ?? []
    }

    /// Non-blocking version of `snapshot()`. The viewer uses this so the main thread isn't
    /// blocked by `queue.sync` while the core queue is processing a heavy write burst.
    public static func snapshotAsync() async -> [LogEntry] {
        guard let store = runtime.store else { return [] }
        return await store.snapshotAsync()
    }

    /// All entries on disk — **including previous sessions** (independent of ring buffer capacity).
    /// Heavy file I/O runs in the background; the caller (e.g. the main thread) is not blocked.
    /// For large histories, prefer paginated reads via `loadPersistedPage(before:minimumEntries:)`
    /// to avoid loading everything into memory at once (the viewer uses this).
    public static func loadPersistedEntries() async -> [LogEntry] {
        guard let store = runtime.store else { return [] }
        return await store.loadPersisted()
    }

    /// Reads on-disk history **paginated** — newest to oldest. Pass `before: nil` for the first
    /// page; for the next (older) page, pass the previous page's `nextCursor`. `nextCursor == nil`
    /// means the end of history. A page is assembled from whole NDJSON files until it contains at
    /// least `minimumEntries` entries (files are never split).
    public static func loadPersistedPage(
        before cursor: String? = nil,
        minimumEntries: Int = 500
    ) async -> PersistedLogPage {
        guard let store = runtime.store else { return PersistedLogPage(entries: [], nextCursor: nil) }
        return await store.loadPersistedPage(before: cursor, minimumEntries: minimumEntries)
    }

    /// A stream that live-broadcasts new entries.
    public static func stream() -> AsyncStream<LogEntry> {
        runtime.store?.makeStream() ?? AsyncStream { $0.finish() }
    }

    /// Clears all logs (memory + disk).
    public static func clear() {
        runtime.store?.clear()
    }

    /// Merges all logs into a single file and returns a shareable URL (async, non-blocking).
    public static func exportFileURL() async -> URL? {
        guard let store = runtime.store else { return nil }
        return await store.exportFileURL()
    }

    /// Writes the given entries to a shareable file (async, non-blocking). The viewer uses this
    /// to share the currently **filtered** list; entry selection is up to the caller.
    public static func exportFileURL(entries: [LogEntry]) async -> URL? {
        guard let store = runtime.store else { return nil }
        return await store.exportFileURL(entries: entries)
    }

    /// Writes the given entries to a **raw NDJSON** (.ndjson — one JSON `LogEntry` per line) file.
    /// Same schema as the on-disk format: can be fed losslessly into jq/backend analysis/other tools.
    public static func exportNDJSONFileURL(entries: [LogEntry]) async -> URL? {
        guard let store = runtime.store else { return nil }
        return await store.exportNDJSONFileURL(entries: entries)
    }
}

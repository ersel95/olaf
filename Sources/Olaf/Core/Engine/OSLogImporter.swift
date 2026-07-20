import Foundation
import OSLog

extension Olaf {

    /// Imports **this process's** entries from the system's OSLog store into Olaf — including
    /// `os_log`/`Logger` output from other SDKs. This way, logs from libraries that don't know
    /// about Olaf also show up/get shared in the viewer's single list.
    ///
    /// - Entries are added with their **original timestamp** but shown in insertion order in the
    ///   list: the imported block appears as a group above the point where the call was made.
    /// - To keep Olaf's own OSLog mirror (`mirrorsToOSLog`) from producing duplicate entries, if
    ///   `excludingSubsystems` is not given, the **main bundle identifier** (the default mirror
    ///   subsystem) is excluded; if you gave the mirror a custom `subsystem`, pass that instead.
    /// - The heavy read happens in the background at `.utility` priority; the caller is not blocked.
    ///
    /// - Parameters:
    ///   - since: Entries are read from this date onward (e.g. `Date().addingTimeInterval(-3600)`).
    ///   - category: The Olaf category entries will fall under (default `.oslog`).
    ///   - excludingSubsystems: Subsystems to skip. `nil` → the main bundle id is excluded.
    /// - Returns: The number of imported entries. `0` if Olaf hasn't been started.
    @discardableResult
    public static func importOSLogEntries(
        since: Date,
        category: LogCategory = .oslog,
        excludingSubsystems: [String]? = nil
    ) async throws -> Int {
        guard let store = runtime.store else { return 0 }
        let excluded = Set(excludingSubsystems ?? [Bundle.main.bundleIdentifier ?? "com.olaf"])

        return try await Task.detached(priority: .utility) {
            let osStore = try OSLogStore(scope: .currentProcessIdentifier)
            let position = osStore.position(date: since)
            var imported = 0
            for case let log as OSLogEntryLog in try osStore.getEntries(at: position) {
                guard !excluded.contains(log.subsystem) else { continue }
                store.ingest(
                    date: log.date,
                    level: mapOSLogLevel(log.level),
                    category: category,
                    rawMessage: log.composedMessage,
                    rawMetadata: [
                        "source": "oslog",
                        "subsystem": log.subsystem,
                        "osCategory": log.category
                    ],
                    file: "OSLog",
                    line: 0,
                    function: "-",
                    thread: "-"
                )
                imported += 1
            }
            return imported
        }.value
    }

    /// OSLog → Olaf level mapping. (internal: tested.)
    static func mapOSLogLevel(_ level: OSLogEntryLog.Level) -> LogLevel {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .error: return .error
        case .fault: return .critical
        case .undefined: return .info
        @unknown default: return .info
        }
    }
}

import Foundation
import os

/// Mirrors entries to `os.Logger` → visible in Console.app and the system log stream.
/// Only ever called from `LogStore`'s serial queue.
final class OSLogMirror: @unchecked Sendable {

    private let subsystem: String
    private var loggers: [String: Logger] = [:]

    init(subsystem: String) {
        self.subsystem = subsystem
    }

    func log(_ entry: LogEntry) {
        let logger = logger(for: entry.category.rawValue)
        // `.public`: the message is RAW and visible in the clear in Console.app — Olaf must only
        // run in non-prod (sensitive-data responsibility lies with the host; see CLAUDE.md/README rules).
        logger.log(level: entry.level.osLogType, "\(entry.message, privacy: .public)")
    }

    private func logger(for category: String) -> Logger {
        if let existing = loggers[category] { return existing }
        let logger = Logger(subsystem: subsystem, category: category)
        loggers[category] = logger
        return logger
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info, .notice: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

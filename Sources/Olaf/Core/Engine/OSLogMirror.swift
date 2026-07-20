import Foundation
import os

/// Redakte edilmiş kayıtları `os.Logger`'a yansıtır → Console.app ve sistem log akışında görünür.
/// Yalnız `LogStore`'un serial kuyruğundan çağrılır.
final class OSLogMirror: @unchecked Sendable {

    private let subsystem: String
    private var loggers: [String: Logger] = [:]

    init(subsystem: String) {
        self.subsystem = subsystem
    }

    func log(_ entry: LogEntry) {
        let logger = logger(for: entry.category.rawValue)
        // Mesaj zaten redakte; yine de `.public` ile veriyoruz çünkü hassas veri kalmadı.
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

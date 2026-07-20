import Foundation

/// Log severity level. Aligned with the `swift-log` and OSLog level model.
public enum LogLevel: Int, Comparable, Sendable, Codable, CaseIterable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Stable short name for display/matching (`INFO`, `ERROR`...).
    public var name: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }

    /// Symbol for visually distinguishing the level in the viewer.
    public var symbol: String {
        switch self {
        case .trace: return "🔬"
        case .debug: return "🐞"
        case .info: return "ℹ️"
        case .notice: return "📌"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🔥"
        }
    }
}

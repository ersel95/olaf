import Foundation

/// Log önem seviyesi. `swift-log` ve OSLog seviye modeliyle hizalıdır.
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

    /// Görüntüleme/eşleştirme için kararlı kısa ad (`INFO`, `ERROR`...).
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

    /// Viewer'da seviyeyi göz ile ayırt etmek için sembol.
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

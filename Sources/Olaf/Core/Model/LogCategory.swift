import Foundation

/// Module-based log grouping. Since it's string-backed, each project can add its own
/// categories via `extension LogCategory`.
public struct LogCategory: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ value: String) {
        self.rawValue = value
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    // Suggested common categories — projects can extend these.
    public static let general: LogCategory = "general"
    public static let auth: LogCategory = "auth"
    public static let payment: LogCategory = "payment"
    public static let network: LogCategory = "network"
    public static let session: LogCategory = "session"
    public static let security: LogCategory = "security"
    /// Screen transitions (push/sheet/popup/root). `Olaf.trackScreen(_:kind:)` writes to this category.
    public static let navigation: LogCategory = "navigation"
    /// Entries imported from the system's OSLog store (`Olaf.importOSLogEntries`).
    public static let oslog: LogCategory = "oslog"
    /// Codable decoding errors (`Olaf.logDecodingError` / `OlafDecoding.decode`).
    public static let decoding: LogCategory = "decoding"
}

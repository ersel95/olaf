import Foundation

/// Modül bazlı log gruplaması. String-backed olduğu için her proje kendi
/// kategorilerini `extension LogCategory` ile ekleyebilir.
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

    // Önerilen ortak kategoriler — projeler genişletebilir.
    public static let general: LogCategory = "general"
    public static let auth: LogCategory = "auth"
    public static let payment: LogCategory = "payment"
    public static let network: LogCategory = "network"
    public static let session: LogCategory = "session"
    public static let security: LogCategory = "security"
    /// Ekran geçişleri (push/sheet/popup/root). `Olaf.trackScreen(_:kind:)` bu kategoriye yazar.
    public static let navigation: LogCategory = "navigation"
    /// Sistemin OSLog deposundan içe aktarılan kayıtlar (`Olaf.importOSLogEntries`).
    public static let oslog: LogCategory = "oslog"
    /// Codable decode hataları (`Olaf.logDecodingError` / `OlafDecoding.decode`).
    public static let decoding: LogCategory = "decoding"
}

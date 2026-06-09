import Foundation
import OlafCore

/// `multipart/form-data` `report` JSON alanının birebir karşılığı (plan §1 veri sözleşmesi).
///
/// ```jsonc
/// { "app": {...}, "device": {...}, "report": {...}, "entries": [ /* ham LogEntry[] */ ] }
/// ```
public struct OlafReportPayload: Codable, Sendable {

    public struct App: Codable, Sendable {
        public let bundleId: String
        public let version: String
        public let build: String
        public let environment: String
    }

    public struct Device: Codable, Sendable {
        public let id: String
        public let name: String?
        public let model: String
        public let osVersion: String
        public let locale: String
        public let screen: String
    }

    public struct Report: Codable, Sendable {
        public let whatHappened: String
        public let whatExpected: String
        public let capturedAt: String
        public let sessionId: String
    }

    public let app: App
    public let device: Device
    public let report: Report
    /// Ham `LogEntry[]` — **TÜM kategoriler**, tek kaynak. Kategori bozulmadan gider.
    public let entries: [LogEntry]

    public init(app: App, device: Device, report: Report, entries: [LogEntry]) {
        self.app = app
        self.device = device
        self.report = report
        self.entries = entries
    }

    /// `report` alanı için JSON encode. `entries` ham LogEntry kodlamasını korur.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

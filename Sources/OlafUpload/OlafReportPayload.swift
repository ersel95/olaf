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

    /// Raporun alındığı andaki anlık cihaz durumu (telemetri). Hepsi cihaz-durumu,
    /// PII değil. Toplanamayan alanlar `nil` (server'da jsonb olarak saklanır).
    public struct Telemetry: Codable, Sendable {
        public let timezone: String?          // "Asia/Baku"
        public let screenScale: Double?       // 3.0
        public let screenPoints: String?      // "390x844" (points)
        public let networkType: String?       // wifi/cellular/wired/none/unknown
        public let batteryLevel: Int?         // 0–100, nil = bilinmiyor
        public let batteryState: String?      // charging/full/unplugged/unknown
        public let lowPowerMode: Bool?
        public let thermalState: String?      // nominal/fair/serious/critical
        public let orientation: String?       // portrait/landscapeLeft/...
        public let freeDiskBytes: Int64?
        public let totalDiskBytes: Int64?
        public let totalMemoryBytes: Int64?
        public let appMemoryBytes: Int64?

        public init(
            timezone: String?, screenScale: Double?, screenPoints: String?,
            networkType: String?, batteryLevel: Int?, batteryState: String?,
            lowPowerMode: Bool?, thermalState: String?, orientation: String?,
            freeDiskBytes: Int64?, totalDiskBytes: Int64?,
            totalMemoryBytes: Int64?, appMemoryBytes: Int64?
        ) {
            self.timezone = timezone
            self.screenScale = screenScale
            self.screenPoints = screenPoints
            self.networkType = networkType
            self.batteryLevel = batteryLevel
            self.batteryState = batteryState
            self.lowPowerMode = lowPowerMode
            self.thermalState = thermalState
            self.orientation = orientation
            self.freeDiskBytes = freeDiskBytes
            self.totalDiskBytes = totalDiskBytes
            self.totalMemoryBytes = totalMemoryBytes
            self.appMemoryBytes = appMemoryBytes
        }
    }

    public let app: App
    public let device: Device
    public let report: Report
    /// Anlık cihaz telemetrisi (opsiyonel — toplanamazsa `nil`).
    public let telemetry: Telemetry?
    /// Ham `LogEntry[]` — **TÜM kategoriler**, tek kaynak. Kategori bozulmadan gider.
    public let entries: [LogEntry]

    public init(
        app: App,
        device: Device,
        report: Report,
        telemetry: Telemetry? = nil,
        entries: [LogEntry]
    ) {
        self.app = app
        self.device = device
        self.report = report
        self.telemetry = telemetry
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

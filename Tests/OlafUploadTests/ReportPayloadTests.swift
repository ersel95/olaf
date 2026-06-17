import XCTest
import OlafCore
@testable import OlafUpload

final class ReportPayloadTests: XCTestCase {

    func testPayloadEncodesContractFields() throws {
        let entry = LogEntry(
            date: Date(timeIntervalSince1970: 0),
            level: .info,
            category: .navigation,
            message: "dashboard",
            metadata: ["screen": "dashboard", "kind": "push"],
            file: "X.swift",
            line: 1,
            function: "f()",
            thread: "main",
            sessionID: "s1"
        )
        let payload = OlafReportPayload(
            app: .init(bundleId: "com.example.demo", version: "1.0", build: "10", environment: "staging"),
            device: .init(id: "dev-1", name: "Tester", model: "iPhone15,3", osVersion: "17.5", locale: "en_US", screen: "1179x2556"),
            report: .init(whatHappened: "crash", whatExpected: "no crash", capturedAt: "2026-06-08T10:22:00Z", sessionId: "s1"),
            entries: [entry]
        )

        let data = try payload.encodedJSON()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["app"])
        XCTAssertNotNil(object?["device"])
        XCTAssertNotNil(object?["report"])

        let app = object?["app"] as? [String: Any]
        XCTAssertEqual(app?["bundleId"] as? String, "com.example.demo")

        let device = object?["device"] as? [String: Any]
        XCTAssertEqual(device?["id"] as? String, "dev-1")
        XCTAssertEqual(device?["name"] as? String, "Tester")

        let entries = object?["entries"] as? [[String: Any]]
        XCTAssertEqual(entries?.count, 1)
        // Kategori korunmalı (ham LogEntry, bozulmadan).
        XCTAssertEqual(entries?.first?["category"] as? String, "navigation")
    }

    func testPayloadEncodesTelemetryWhenPresent() throws {
        let telemetry = OlafReportPayload.Telemetry(
            timezone: "Asia/Baku", screenScale: 3.0, screenPoints: "393x852",
            networkType: "wifi", batteryLevel: 84, batteryState: "unplugged",
            lowPowerMode: false, thermalState: "nominal", orientation: "portrait",
            freeDiskBytes: 12_345_678, totalDiskBytes: 128_000_000_000,
            totalMemoryBytes: 6_000_000_000, appMemoryBytes: 90_000_000
        )
        let payload = OlafReportPayload(
            app: .init(bundleId: "com.example.demo", version: "1.0", build: "10", environment: "staging"),
            device: .init(id: "dev-1", name: "Tester", model: "iPhone15,3", osVersion: "17.5", locale: "en_US", screen: "1179x2556"),
            report: .init(whatHappened: "x", whatExpected: "y", capturedAt: "2026-06-08T10:22:00Z", sessionId: "s1"),
            telemetry: telemetry,
            entries: []
        )

        let object = try JSONSerialization.jsonObject(
            with: payload.encodedJSON()
        ) as? [String: Any]
        let t = object?["telemetry"] as? [String: Any]
        XCTAssertEqual(t?["timezone"] as? String, "Asia/Baku")
        XCTAssertEqual(t?["networkType"] as? String, "wifi")
        XCTAssertEqual(t?["batteryLevel"] as? Int, 84)
        XCTAssertEqual(t?["thermalState"] as? String, "nominal")
    }

    func testPayloadOmitsTelemetryWhenNil() throws {
        let payload = OlafReportPayload(
            app: .init(bundleId: "b", version: "1", build: "1", environment: "staging"),
            device: .init(id: "d", name: nil, model: "m", osVersion: "17", locale: "en", screen: "1x1"),
            report: .init(whatHappened: "x", whatExpected: "y", capturedAt: "z", sessionId: "s"),
            entries: []
        )
        let object = try JSONSerialization.jsonObject(
            with: payload.encodedJSON()
        ) as? [String: Any]
        XCTAssertNil(object?["telemetry"])
    }

    func testRemoteConfigDefaultsToDisabledOnMissingKeys() throws {
        let data = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(OlafRemoteConfig.self, from: data)
        XCTAssertFalse(config.captureEnabled)
        XCTAssertGreaterThan(config.maxScreenshotBytes, 0)
    }
}

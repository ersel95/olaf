import XCTest
@testable import Olaf

final class NetworkTimingAndPendingTests: XCTestCase {

    // MARK: - Timing metadata

    func testTimingMetadataKeys() {
        var event = NetworkLogEvent(
            method: "GET", url: "https://a.com", statusCode: 200, durationMs: 100,
            requestBytes: 0, responseBytes: 0, error: nil, requestBody: nil, responseBody: nil
        )
        event.timing = NetworkTimingMetrics(
            dnsMs: 12, connectMs: 34, tlsMs: 56, ttfbMs: 78,
            protocolName: "h2", reusedConnection: false
        )
        let metadata = NetworkLogComposer.metadata(for: event)
        XCTAssertEqual(metadata["t.dnsMs"], "12")
        XCTAssertEqual(metadata["t.connectMs"], "34")
        XCTAssertEqual(metadata["t.tlsMs"], "56")
        XCTAssertEqual(metadata["t.ttfbMs"], "78")
        XCTAssertEqual(metadata["t.protocol"], "h2")
        XCTAssertEqual(metadata["t.reused"], "false")
    }

    func testTimingOmittedWhenAbsent() {
        let event = NetworkLogEvent(
            method: "GET", url: "https://a.com", statusCode: 200, durationMs: 100,
            requestBytes: 0, responseBytes: 0, error: nil, requestBody: nil, responseBody: nil
        )
        let metadata = NetworkLogComposer.metadata(for: event)
        XCTAssertNil(metadata["t.dnsMs"])
        XCTAssertNil(metadata["t.protocol"])
    }

    func testViewerParsesTimingKeys() {
        let entry = LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: [
                "method": "GET", "url": "https://a.com",
                "t.dnsMs": "5", "t.ttfbMs": "40", "t.protocol": "h3", "t.reused": "true"
            ],
            file: "F.swift", line: 1, function: "f()", thread: "main"
        )
        let info = NetworkLogInfo(entry: entry)
        XCTAssertEqual(info?.dnsMs, 5)
        XCTAssertEqual(info?.ttfbMs, 40)
        XCTAssertEqual(info?.protocolName, "h3")
        XCTAssertEqual(info?.reusedConnection, true)
        XCTAssertEqual(info?.hasTimings, true)

        let plain = LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: ["method": "GET", "url": "https://a.com"],
            file: "F.swift", line: 1, function: "f()", thread: "main"
        )
        XCTAssertEqual(NetworkLogInfo(entry: plain)?.hasTimings, false)
    }

    // MARK: - Active request registry

    func testPendingRegistryLifecycle() {
        let registry = PendingRequestRegistry.shared
        registry.removeAll()

        let first = registry.register(method: "GET", url: "https://a.com/1")
        let second = registry.register(method: "POST", url: "https://a.com/2")
        XCTAssertEqual(registry.snapshot.count, 2)
        // Sorted with the oldest first.
        XCTAssertEqual(registry.snapshot.first?.id, first)
        XCTAssertEqual(OlafNetwork.pendingRequests.count, 2)

        registry.unregister(first)
        XCTAssertEqual(registry.snapshot.map(\.id), [second])

        registry.unregister(second)
        XCTAssertTrue(registry.snapshot.isEmpty)
        // An unknown id is a no-op.
        registry.unregister(first)
        XCTAssertTrue(registry.snapshot.isEmpty)
    }
}

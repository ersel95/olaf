import XCTest
@testable import Olaf

final class NetworkStatsTests: XCTestCase {

    private func networkEntry(
        method: String = "GET",
        url: String = "https://api.example.com/x",
        status: Int? = 200,
        durationMs: Int? = 100,
        error: String? = nil,
        cancelled: Bool = false,
        reqBytes: Int = 10,
        respBytes: Int = 20
    ) -> LogEntry {
        let event = NetworkLogEvent(
            method: method, url: url, statusCode: status, durationMs: durationMs ?? 0,
            requestBytes: reqBytes, responseBytes: respBytes, error: error,
            requestBody: nil, responseBody: nil, cancelled: cancelled
        )
        var metadata = NetworkLogComposer.metadata(for: event)
        if durationMs == nil { metadata["durationMs"] = nil }
        return LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: metadata, file: "F.swift", line: 1, function: "f()", thread: "main"
        )
    }

    func testComputeAggregates() {
        let entries = [
            networkEntry(method: "GET", url: "https://a.com/1", status: 200, durationMs: 100),
            networkEntry(method: "GET", url: "https://a.com/2", status: 404, durationMs: 300),
            networkEntry(method: "POST", url: "https://b.com/3", status: 500, durationMs: 500),
            networkEntry(method: "GET", url: "https://a.com/4", status: nil, durationMs: 50, error: "timeout"),
            networkEntry(method: "GET", url: "https://a.com/5", status: nil, durationMs: 10, cancelled: true),
            // A non-network record doesn't count:
            LogEntry(date: Date(), level: .info, category: .general, message: "app",
                     metadata: [:], file: "F.swift", line: 1, function: "f()", thread: "main")
        ]

        let stats = NetworkStats.compute(from: entries)
        XCTAssertEqual(stats.totalRequests, 5)
        XCTAssertEqual(stats.failureCount, 3)          // 404 + 500 + timeout (excluding cancelled)
        XCTAssertEqual(stats.cancelledCount, 1)
        XCTAssertEqual(stats.failurePercent, 60)
        XCTAssertEqual(stats.averageDurationMs, (100 + 300 + 500 + 50 + 10) / 5)
        XCTAssertEqual(stats.totalRequestBytes, 50)
        XCTAssertEqual(stats.totalResponseBytes, 100)

        // Methods descending.
        XCTAssertEqual(stats.methodCounts.first?.name, "GET")
        XCTAssertEqual(stats.methodCounts.first?.count, 4)

        // Status classes in fixed order, zeros omitted.
        XCTAssertEqual(stats.statusClassCounts.map(\.name), ["2xx", "4xx", "5xx", "Error", "Cancelled"])

        // Hosts descending.
        XCTAssertEqual(stats.hostCounts.first?.name, "a.com")
        XCTAssertEqual(stats.hostCounts.first?.count, 4)

        // Slowest first.
        XCTAssertEqual(stats.slowest.first?.durationMs, 500)
        XCTAssertEqual(stats.slowest.first?.path, "/3")
    }

    func testEmptyInput() {
        let stats = NetworkStats.compute(from: [])
        XCTAssertEqual(stats.totalRequests, 0)
        XCTAssertNil(stats.averageDurationMs)
        XCTAssertEqual(stats.failurePercent, 0)
        XCTAssertTrue(stats.methodCounts.isEmpty)
    }
}

import XCTest
@testable import Olaf

final class HARExporterTests: XCTestCase {

    private func networkEntry() -> LogEntry {
        var event = NetworkLogEvent(
            method: "POST",
            url: "https://api.example.com/v1/pay?id=7&x=1",
            statusCode: 201,
            durationMs: 120,
            requestBytes: 18,
            responseBytes: 64,
            error: nil,
            requestBody: #"{"amount":50}"#,
            responseBody: #"{"ok":true}"#
        )
        event.requestHeaders = ["Content-Type": "application/json", "Authorization": "Bearer x"]
        event.responseHeaders = ["Content-Type": "application/json"]
        event.timing = NetworkTimingMetrics(
            dnsMs: 10, connectMs: 20, tlsMs: 15, ttfbMs: 60,
            protocolName: "h2", reusedConnection: false
        )
        return LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: NetworkLogComposer.metadata(for: event),
            file: "F.swift", line: 1, function: "f()", thread: "main"
        )
    }

    private func plainEntry() -> LogEntry {
        LogEntry(
            date: Date(), level: .info, category: .general, message: "app log",
            metadata: [:], file: "F.swift", line: 1, function: "f()", thread: "main"
        )
    }

    func testProducesValidHARStructure() throws {
        let text = try XCTUnwrap(HARExporter.harDocument(from: [plainEntry(), networkEntry()]))
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let log = try XCTUnwrap(root["log"] as? [String: Any])
        XCTAssertEqual(log["version"] as? String, "1.2")

        // Network olmayan kayıt atlanır.
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry["time"] as? Int, 120)

        let request = try XCTUnwrap(entry["request"] as? [String: Any])
        XCTAssertEqual(request["method"] as? String, "POST")
        XCTAssertEqual(request["httpVersion"] as? String, "HTTP/2")
        let query = try XCTUnwrap(request["queryString"] as? [[String: String]])
        XCTAssertEqual(query.count, 2)
        let postData = try XCTUnwrap(request["postData"] as? [String: Any])
        XCTAssertEqual(postData["mimeType"] as? String, "application/json")

        let response = try XCTUnwrap(entry["response"] as? [String: Any])
        XCTAssertEqual(response["status"] as? Int, 201)
        let content = try XCTUnwrap(response["content"] as? [String: Any])
        XCTAssertEqual(content["text"] as? String, #"{"ok":true}"#)

        let timings = try XCTUnwrap(entry["timings"] as? [String: Any])
        XCTAssertEqual(timings["dns"] as? Int, 10)
        XCTAssertEqual(timings["wait"] as? Int, 60)
        XCTAssertEqual(timings["ssl"] as? Int, 15)
        // receive = toplam - (dns + connect + wait) = 120 - 90 = 30
        XCTAssertEqual(timings["receive"] as? Int, 30)
    }

    func testEmptyInputStillProducesValidDocument() throws {
        let text = try XCTUnwrap(HARExporter.harDocument(from: []))
        let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let log = root?["log"] as? [String: Any]
        XCTAssertEqual((log?["entries"] as? [Any])?.count, 0)
    }
}

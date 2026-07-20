import XCTest
@testable import Olaf

final class PostmanExporterTests: XCTestCase {

    private func networkEntry(method: String = "POST", url: String = "https://api.example.com:8443/v1/pay?id=7") -> LogEntry {
        var event = NetworkLogEvent(
            method: method, url: url, statusCode: 200, durationMs: 10,
            requestBytes: 0, responseBytes: 0, error: nil,
            requestBody: #"{"amount":50}"#, responseBody: nil
        )
        event.requestHeaders = ["Content-Type": "application/json"]
        return LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: NetworkLogComposer.metadata(for: event),
            file: "F.swift", line: 1, function: "f()", thread: "main"
        )
    }

    func testCollectionStructureAndDedupe() throws {
        // Same method+URL twice → single item; different method → separate item.
        let entries = [
            networkEntry(),
            networkEntry(),
            networkEntry(method: "GET")
        ]
        let text = try XCTUnwrap(PostmanExporter.collection(from: entries))
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )

        let info = try XCTUnwrap(root["info"] as? [String: Any])
        XCTAssertEqual(info["schema"] as? String, "https://schema.getpostman.com/json/collection/v2.1.0/collection.json")

        let items = try XCTUnwrap(root["item"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)

        let request = try XCTUnwrap(items[0]["request"] as? [String: Any])
        XCTAssertEqual(request["method"] as? String, "POST")

        let urlObject = try XCTUnwrap(request["url"] as? [String: Any])
        XCTAssertEqual(urlObject["protocol"] as? String, "https")
        XCTAssertEqual(urlObject["host"] as? [String], ["api", "example", "com"])
        XCTAssertEqual(urlObject["port"] as? String, "8443")
        XCTAssertEqual(urlObject["path"] as? [String], ["v1", "pay"])
        XCTAssertEqual((urlObject["query"] as? [[String: String]])?.first?["key"], "id")

        let body = try XCTUnwrap(request["body"] as? [String: Any])
        XCTAssertEqual(body["mode"] as? String, "raw")
        XCTAssertEqual(body["raw"] as? String, #"{"amount":50}"#)
    }

    func testNonNetworkEntriesSkipped() throws {
        let plain = LogEntry(
            date: Date(), level: .info, category: .general, message: "m",
            metadata: [:], file: "F.swift", line: 1, function: "f()", thread: "main"
        )
        let text = try XCTUnwrap(PostmanExporter.collection(from: [plain]))
        let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        XCTAssertEqual((root?["item"] as? [Any])?.count, 0)
    }
}

import XCTest
@testable import Olaf

/// `NetworkLogInfo`'s metadata parsing — keys must stay aligned with `NetworkLogComposer`.
final class NetworkLogInfoTests: XCTestCase {

    private func networkEntry(metadata: [String: String]) -> LogEntry {
        LogEntry(
            date: Date(), level: .info, category: .network, message: "GET https://x",
            metadata: metadata, file: "F.swift", line: 1, function: "f()", thread: "main"
        )
    }

    func testNonNetworkCategoryReturnsNil() {
        let entry = LogEntry(
            date: Date(), level: .info, category: .general, message: "m",
            metadata: ["method": "GET"], file: "F.swift", line: 1, function: "f()", thread: "main"
        )
        XCTAssertNil(NetworkLogInfo(entry: entry))
    }

    func testComposerMetadataRoundtrip() {
        // The metadata produced by the composer must be readable back verbatim on the viewer side.
        var event = NetworkLogEvent(
            method: "POST",
            url: "https://api.example.com/v1/pay?id=7",
            statusCode: 201,
            durationMs: 88,
            requestBytes: 10,
            responseBytes: 20,
            error: nil,
            requestBody: #"{"a":1}"#,
            responseBody: #"{"ok":true}"#
        )
        event.requestHeaders = ["Authorization": "Bearer x", "Accept": "application/json"]
        event.responseHeaders = ["Content-Type": "application/json"]

        let info = NetworkLogInfo(entry: networkEntry(metadata: NetworkLogComposer.metadata(for: event)))
        let unwrapped = try! XCTUnwrap(info)

        XCTAssertEqual(unwrapped.method, "POST")
        XCTAssertEqual(unwrapped.statusCode, 201)
        XCTAssertEqual(unwrapped.durationMs, 88)
        XCTAssertEqual(unwrapped.requestBytes, 10)
        XCTAssertEqual(unwrapped.responseBytes, 20)
        XCTAssertEqual(unwrapped.requestBody, #"{"a":1}"#)
        XCTAssertEqual(unwrapped.responseBody, #"{"ok":true}"#)
        XCTAssertFalse(unwrapped.cancelled)
        // Headers are parsed from the prefix and sorted by name.
        XCTAssertEqual(unwrapped.requestHeaders.map(\.key), ["Accept", "Authorization"])
        XCTAssertEqual(unwrapped.responseHeaders.first?.value, "application/json")
        // URL parsing.
        XCTAssertEqual(unwrapped.host, "api.example.com")
        XCTAssertEqual(unwrapped.path, "/v1/pay?id=7")
        XCTAssertFalse(unwrapped.isFailure)
    }

    func testCancelledParsedAndNotFailure() {
        let info = NetworkLogInfo(entry: networkEntry(metadata: [
            "method": "GET", "url": "https://a.com", "durationMs": "5",
            "reqBytes": "0", "respBytes": "0", "cancelled": "true"
        ]))
        XCTAssertEqual(info?.cancelled, true)
        XCTAssertEqual(info?.isFailure, false)   // cancellation is not an error
    }

    func testFailureDetection() {
        let notFound = NetworkLogInfo(entry: networkEntry(metadata: ["status": "404"]))
        XCTAssertEqual(notFound?.isFailure, true)
        let failed = NetworkLogInfo(entry: networkEntry(metadata: ["error": "timeout"]))
        XCTAssertEqual(failed?.isFailure, true)
        let ok = NetworkLogInfo(entry: networkEntry(metadata: ["status": "200"]))
        XCTAssertEqual(ok?.isFailure, false)
    }
}

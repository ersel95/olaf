import XCTest
@testable import Olaf

final class CurlBuilderTests: XCTestCase {

    private func info(metadata: [String: String]) -> NetworkLogInfo {
        let entry = LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: metadata, file: "F.swift", line: 1, function: "f()", thread: "main"
        )
        return NetworkLogInfo(entry: entry)!
    }

    func testCurlContainsMethodURLHeadersAndBody() {
        let curl = CurlBuilder.curl(from: info(metadata: [
            "method": "POST",
            "url": "https://api.example.com/pay",
            "reqH.Content-Type": "application/json",
            "requestBody": #"{"amount":50}"#
        ]))
        XCTAssertTrue(curl.hasPrefix("curl -X POST 'https://api.example.com/pay'"))
        XCTAssertTrue(curl.contains("-H 'Content-Type: application/json'"))
        XCTAssertTrue(curl.contains(#"-d '{"amount":50}'"#))
    }

    func testSingleQuotesAreShellEscaped() {
        let curl = CurlBuilder.curl(from: info(metadata: [
            "method": "GET",
            "url": "https://a.com",
            "reqH.X-Note": "it's here"
        ]))
        // A single quote must be escaped as `'\''`; otherwise the copied command breaks in the shell.
        XCTAssertTrue(curl.contains(#"'X-Note: it'\''s here'"#))
    }

    func testMissingMethodDefaultsToGETAndNoBodyFlag() {
        let curl = CurlBuilder.curl(from: info(metadata: ["url": "https://a.com"]))
        XCTAssertTrue(curl.hasPrefix("curl -X GET"))
        XCTAssertFalse(curl.contains("-d "))
    }
}

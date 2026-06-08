import XCTest
@testable import OlafUI
import OlafCore

final class ShareFormatterTests: XCTestCase {

    private func networkEntry() -> (LogEntry, NetworkLogInfo) {
        let entry = LogEntry(
            date: Date(timeIntervalSince1970: 0),
            level: .info,
            category: .network,
            message: "POST https://api.example.com/x → 200 (12ms)",
            metadata: [
                "method": "POST",
                "url": "https://api.example.com/x",
                "status": "200",
                "durationMs": "12",
                "reqH.Accept": "application/json",
                "respH.Content-Type": "application/json",
                "requestBody": "{\"a\":1}",
                "responseBody": "{\"ok\":true}"
            ],
            file: "Test.swift", line: 1, function: "f()", thread: "main"
        )
        return (entry, NetworkLogInfo(entry: entry)!)
    }

    func testSimpleLogHasSummaryAndHeadersNoBody() {
        let (entry, info) = networkEntry()
        let text = ShareFormatter.simpleNetworkLog(entry: entry, info: info)
        XCTAssertTrue(text.contains("POST https://api.example.com/x"))
        XCTAssertTrue(text.contains("Durum: 200"))
        XCTAssertTrue(text.contains("Accept: application/json"))
        XCTAssertFalse(text.contains("\"ok\":true")) // gövde simple'da yok
    }

    func testFullLogIncludesBodies() {
        let (entry, info) = networkEntry()
        let text = ShareFormatter.fullNetworkLog(entry: entry, info: info)
        XCTAssertTrue(text.contains("İstek Gövdesi"))
        XCTAssertTrue(text.contains("\"a\":1"))
        XCTAssertTrue(text.contains("\"ok\":true"))
        // Tam log artık cURL bloğunu da içerir.
        XCTAssertTrue(text.contains("-- cURL --"))
        XCTAssertTrue(text.contains("curl -X POST"))
    }

    func testCurlContainsMethodURLHeaderAndBody() {
        let (_, info) = networkEntry()
        let curl = CurlBuilder.curl(from: info)
        XCTAssertTrue(curl.contains("curl -X POST"))
        XCTAssertTrue(curl.contains("'https://api.example.com/x'"))
        XCTAssertTrue(curl.contains("-H 'Accept: application/json'"))
        XCTAssertTrue(curl.contains("-d "))
    }

    func testLogDetailForNonNetwork() {
        let entry = LogEntry(
            date: Date(timeIntervalSince1970: 0),
            level: .warning, category: .auth, message: "uyarı",
            metadata: ["k": "v"], file: "A.swift", line: 9, function: "g()", thread: "main"
        )
        let text = ShareFormatter.logDetail(entry: entry)
        XCTAssertTrue(text.contains("[WARNING] [auth] uyarı"))
        XCTAssertTrue(text.contains("A.swift:9"))
        XCTAssertTrue(text.contains("k: v"))
    }
}

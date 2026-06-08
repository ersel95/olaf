import XCTest
@testable import OlafNetwork
import OlafCore

final class NetworkLogComposerTests: XCTestCase {

    private func event(status: Int? = 200, error: String? = nil) -> NetworkLogEvent {
        NetworkLogEvent(
            method: "POST",
            url: "https://api.example.com/transfer",
            statusCode: status,
            durationMs: 123,
            requestBytes: 10,
            responseBytes: 20,
            error: error,
            requestBody: nil,
            responseBody: nil
        )
    }

    func testLevelMapping() {
        XCTAssertEqual(NetworkLogComposer.level(statusCode: 200, error: nil), .info)
        XCTAssertEqual(NetworkLogComposer.level(statusCode: 301, error: nil), .info)
        XCTAssertEqual(NetworkLogComposer.level(statusCode: 404, error: nil), .warning)
        XCTAssertEqual(NetworkLogComposer.level(statusCode: 500, error: nil), .error)
        XCTAssertEqual(NetworkLogComposer.level(statusCode: nil, error: "timeout"), .error)
        XCTAssertEqual(NetworkLogComposer.level(statusCode: nil, error: nil), .info)
    }

    func testMessageContainsMethodURLAndStatus() {
        let message = NetworkLogComposer.message(for: event(status: 200))
        XCTAssertTrue(message.contains("POST"))
        XCTAssertTrue(message.contains("https://api.example.com/transfer"))
        XCTAssertTrue(message.contains("200"))
        XCTAssertTrue(message.contains("123ms"))
    }

    func testMetadataKeys() {
        let metadata = NetworkLogComposer.metadata(for: event(status: 200))
        XCTAssertEqual(metadata["method"], "POST")
        XCTAssertEqual(metadata["status"], "200")
        XCTAssertEqual(metadata["durationMs"], "123")
        XCTAssertNil(metadata["error"])
    }

    func testMetadataIncludesErrorWhenPresent() {
        let metadata = NetworkLogComposer.metadata(for: event(status: nil, error: "timed out"))
        XCTAssertEqual(metadata["error"], "timed out")
        XCTAssertNil(metadata["status"])
    }

    func testURLFilterIncludeExclude() {
        let onlyMine = OlafNetworkConfiguration(includedURLs: ["api-gateway"])
        XCTAssertTrue(onlyMine.shouldCapture(URL(string: "https://api-gateway.example.com/x")))
        XCTAssertFalse(onlyMine.shouldCapture(URL(string: "https://firebaseio.com/y")))

        let noSDK = OlafNetworkConfiguration(excludedURLs: ["firebaseio", "crashlytics"])
        XCTAssertFalse(noSDK.shouldCapture(URL(string: "https://app.firebaseio.com/y")))
        XCTAssertTrue(noSDK.shouldCapture(URL(string: "https://api-gateway.example.com/x")))

        // exclude, include'dan önceliklidir
        let both = OlafNetworkConfiguration(includedURLs: ["example.com"], excludedURLs: ["/health"])
        XCTAssertTrue(both.shouldCapture(URL(string: "https://example.com/transfer")))
        XCTAssertFalse(both.shouldCapture(URL(string: "https://example.com/health")))

        XCTAssertTrue(OlafNetworkConfiguration.default.shouldCapture(URL(string: "https://anything.com")))
    }

    func testConfigurationDefaultsOpen() {
        let config = OlafNetworkConfiguration.default
        XCTAssertTrue(config.capturesBodies)  // default açık
        XCTAssertTrue(config.capturesHeaders) // default açık
        XCTAssertEqual(config.category, .network)
    }

    func testMetadataIncludesHeadersAsSeparateKeys() {
        var e = event(status: 200)
        e.requestHeaders = ["Authorization": "Bearer x", "Accept": "application/json"]
        e.responseHeaders = ["Set-Cookie": "sid=123"]
        let metadata = NetworkLogComposer.metadata(for: e)
        XCTAssertEqual(metadata["reqH.Authorization"], "Bearer x") // composer maskelemez; Olaf.log içinde redakte edilir
        XCTAssertEqual(metadata["reqH.Accept"], "application/json")
        XCTAssertEqual(metadata["respH.Set-Cookie"], "sid=123")
    }
}

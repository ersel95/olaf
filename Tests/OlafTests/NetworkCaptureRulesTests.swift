import XCTest
@testable import Olaf

/// Yakalama kuralları: iptal semantiği (composer) + `canInit` kapsam kararları.
final class NetworkCaptureRulesTests: XCTestCase {

    // MARK: - İptal edilen istekler (hata değil, .info)

    private func cancelledEvent() -> NetworkLogEvent {
        NetworkLogEvent(
            method: "GET",
            url: "https://api.example.com/feed",
            statusCode: nil,
            durationMs: 42,
            requestBytes: 0,
            responseBytes: 0,
            error: nil,
            requestBody: nil,
            responseBody: nil,
            cancelled: true
        )
    }

    func testCancelledLevelIsInfoNotError() {
        XCTAssertEqual(NetworkLogComposer.level(statusCode: nil, error: nil, cancelled: true), .info)
        // İptal, hata mesajından önceliklidir (iptalde error zaten boş bırakılır).
        XCTAssertEqual(NetworkLogComposer.level(statusCode: nil, error: "cancelled", cancelled: true), .info)
        // Varsayılan parametre eski davranışı korur.
        XCTAssertEqual(NetworkLogComposer.level(statusCode: nil, error: "timeout"), .error)
    }

    func testCancelledMessageAndMetadata() {
        let event = cancelledEvent()
        XCTAssertTrue(NetworkLogComposer.message(for: event).contains("iptal"))
        let metadata = NetworkLogComposer.metadata(for: event)
        XCTAssertEqual(metadata["cancelled"], "true")
        XCTAssertNil(metadata["error"])
    }

    func testNonCancelledHasNoCancelledKey() {
        var event = cancelledEvent()
        event.cancelled = false
        XCTAssertNil(NetworkLogComposer.metadata(for: event)["cancelled"])
        XCTAssertFalse(NetworkLogComposer.message(for: event).contains("iptal"))
    }

    // MARK: - canInit kapsam kararları

    /// Global config'i değiştiren testler bitince default'a döndürür.
    private func withConfiguration(_ config: OlafNetworkConfiguration, _ body: () -> Void) {
        let previous = OlafNetwork.configuration
        OlafNetwork.configuration = config
        defer { OlafNetwork.configuration = previous }
        body()
    }

    func testCanInitAcceptsOnlyHTTPSchemes() {
        withConfiguration(.default) {
            XCTAssertTrue(OlafURLProtocol.canInit(with: URLRequest(url: URL(string: "https://a.com")!)))
            XCTAssertTrue(OlafURLProtocol.canInit(with: URLRequest(url: URL(string: "http://a.com")!)))
            XCTAssertFalse(OlafURLProtocol.canInit(with: URLRequest(url: URL(string: "ftp://a.com/f")!)))
            XCTAssertFalse(OlafURLProtocol.canInit(with: URLRequest(url: URL(string: "ws://a.com/s")!)))
        }
    }

    func testCanInitSkipsAlreadyHandledRequests() {
        withConfiguration(.default) {
            let mutable = NSMutableURLRequest(url: URL(string: "https://a.com")!)
            URLProtocol.setProperty(true, forKey: "com.olaf.network.handled", in: mutable)
            XCTAssertFalse(OlafURLProtocol.canInit(with: mutable as URLRequest))
        }
    }

    func testCanInitHonorsURLFilters() {
        withConfiguration(OlafNetworkConfiguration(excludedURLs: ["crashlytics"])) {
            XCTAssertFalse(OlafURLProtocol.canInit(with: URLRequest(url: URL(string: "https://api.crashlytics.com/x")!)))
            XCTAssertTrue(OlafURLProtocol.canInit(with: URLRequest(url: URL(string: "https://api.example.com/x")!)))
        }
        withConfiguration(OlafNetworkConfiguration(includedURLs: ["api.example.com"])) {
            XCTAssertTrue(OlafURLProtocol.canInit(with: URLRequest(url: URL(string: "https://api.example.com/x")!)))
            XCTAssertFalse(OlafURLProtocol.canInit(with: URLRequest(url: URL(string: "https://other.com/x")!)))
        }
    }
}

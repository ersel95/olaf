import XCTest
@testable import OlafUpload

final class RemoteConfigTests: XCTestCase {

    private func decode(_ json: String) throws -> OlafRemoteConfig {
        try JSONDecoder().decode(OlafRemoteConfig.self, from: Data(json.utf8))
    }

    func testDecodesRedactionEnabledTrue() throws {
        // C-3: redactionEnabled artık gerçekten decode edilip okunabiliyor.
        let config = try decode(#"{"captureEnabled":true,"redactionEnabled":true,"maxScreenshotBytes":1000}"#)
        XCTAssertTrue(config.captureEnabled)
        XCTAssertTrue(config.redactionEnabled)
        XCTAssertEqual(config.maxScreenshotBytes, 1000)
    }

    func testDecodesRedactionEnabledFalse() throws {
        let config = try decode(#"{"captureEnabled":true,"redactionEnabled":false,"maxScreenshotBytes":1000}"#)
        XCTAssertFalse(config.redactionEnabled)
    }

    func testMissingFieldsDefaultToSafeClosed() throws {
        // Eksik alanlar fail-safe: capture/redaction kapalı varsayılır.
        let config = try decode(#"{}"#)
        XCTAssertFalse(config.captureEnabled)
        XCTAssertFalse(config.redactionEnabled)
        XCTAssertEqual(config.maxScreenshotBytes, 4 * 1_048_576)
    }

    func testDisabledDefaultIsClosed() {
        XCTAssertFalse(OlafRemoteConfig.disabled.captureEnabled)
        XCTAssertFalse(OlafRemoteConfig.disabled.redactionEnabled)
    }
}

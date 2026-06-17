import XCTest
@testable import OlafUpload

final class RemoteConfigTests: XCTestCase {

    private func decode(_ json: String) throws -> OlafRemoteConfig {
        try JSONDecoder().decode(OlafRemoteConfig.self, from: Data(json.utf8))
    }

    func testDecodesCaptureEnabled() throws {
        let config = try decode(#"{"captureEnabled":true,"maxScreenshotBytes":1000}"#)
        XCTAssertTrue(config.captureEnabled)
        XCTAssertEqual(config.maxScreenshotBytes, 1000)
    }

    func testMissingFieldsDefaultToSafeClosed() throws {
        // Eksik alanlar fail-safe: capture kapalı varsayılır.
        let config = try decode(#"{}"#)
        XCTAssertFalse(config.captureEnabled)
        XCTAssertEqual(config.maxScreenshotBytes, 4 * 1_048_576)
    }

    func testDisabledDefaultIsClosed() {
        XCTAssertFalse(OlafRemoteConfig.disabled.captureEnabled)
    }
}

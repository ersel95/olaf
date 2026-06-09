import XCTest
@testable import OlafUpload

final class OptInGateTests: XCTestCase {

    func testDisabledByDefaultIsNoOp() {
        // enabled: false (varsayılan) → configure erken döner, servis kurulmaz.
        OlafUpload.configure(
            enabled: false,
            apiKey: "secret",
            baseURL: URL(string: "https://olaf-api.example.com")!,
            environment: "staging"
        )
        XCTAssertFalse(OlafUpload.isConfigured)
        XCTAssertNil(OlafUpload.bugReportService)
    }

    func testEnabledWithEmptyApiKeyIsNoOp() {
        // enabled: true ama apiKey boş → no-op (app apiKey'den çözülemez).
        OlafUpload.configure(
            enabled: true,
            apiKey: "   ",
            baseURL: URL(string: "https://olaf-api.example.com")!,
            environment: "staging"
        )
        XCTAssertFalse(OlafUpload.isConfigured)
    }
}

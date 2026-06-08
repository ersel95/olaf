import XCTest
@testable import OlafUpload

final class OptInGateTests: XCTestCase {

    func testDisabledByDefaultIsNoOp() {
        // enabled: false (varsayılan) → configure erken döner, servis kurulmaz.
        OlafUpload.configure(
            enabled: false,
            appKey: "demo",
            apiKey: "secret",
            baseURL: URL(string: "https://olaf-api.example.com")!,
            environment: "staging"
        )
        XCTAssertFalse(OlafUpload.isConfigured)
        XCTAssertNil(OlafUpload.bugReportService)
    }

    func testEnabledWithEmptyAppKeyIsNoOp() {
        // enabled: true ama appKey boş → no-op (hangi projeden config çekileceği bilinemez).
        OlafUpload.configure(
            enabled: true,
            appKey: "   ",
            apiKey: "secret",
            baseURL: URL(string: "https://olaf-api.example.com")!,
            environment: "staging"
        )
        XCTAssertFalse(OlafUpload.isConfigured)
    }
}

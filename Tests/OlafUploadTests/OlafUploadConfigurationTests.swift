import XCTest
@testable import OlafUpload

final class OlafUploadConfigurationTests: XCTestCase {

    private func makeConfig(baseURLString: String) -> OlafUploadConfiguration {
        OlafUploadConfiguration(
            enabled: true,
            apiKey: "secret",
            baseURL: URL(string: baseURLString)!,
            environment: "staging"
        )
    }

    func testReportsURLAppendsPath() {
        let config = makeConfig(baseURLString: "https://olaf-api.example.com")
        XCTAssertEqual(config.reportsURL.absoluteString, "https://olaf-api.example.com/api/v1/olaf/reports")
    }

    func testReportsURLHandlesTrailingSlashBase() {
        let config = makeConfig(baseURLString: "https://olaf-api.example.com/")
        XCTAssertEqual(config.reportsURL.absoluteString, "https://olaf-api.example.com/api/v1/olaf/reports")
    }

    func testConfigURLHasNoQuery() {
        // App is resolved from the x-olaf-api-key header now — no appKey query.
        let config = makeConfig(baseURLString: "https://olaf-api.example.com")
        let comps = URLComponents(url: config.configURL, resolvingAgainstBaseURL: false)
        XCTAssertEqual(comps?.path, "/api/v1/olaf/config")
        XCTAssertNil(comps?.queryItems)
    }

    func testCaptureExclusionFragmentsContainHostAndPaths() {
        let config = makeConfig(baseURLString: "https://olaf-api.example.com")
        let fragments = config.captureExclusionFragments
        XCTAssertTrue(fragments.contains("olaf-api.example.com"))
        XCTAssertTrue(fragments.contains("/api/v1/olaf/reports"))
        XCTAssertTrue(fragments.contains("/api/v1/olaf/config"))
    }

    func testScreenshotQualityClamped() {
        let config = OlafUploadConfiguration(baseURL: URL(string: "https://x.example.com")!, screenshotJPEGQuality: 5)
        XCTAssertLessThanOrEqual(config.screenshotJPEGQuality, 1)
        XCTAssertGreaterThanOrEqual(config.screenshotJPEGQuality, 0.1)
    }
}

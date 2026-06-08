import XCTest
@testable import OlafUpload

final class MultipartBodyTests: XCTestCase {

    func testMultipartContainsReportAndScreenshotFields() {
        let reportJSON = #"{"hello":"world"}"#.data(using: .utf8)!
        let screenshot = Data([0xFF, 0xD8, 0xFF, 0xE0])   // JPEG SOI sentinel

        let (body, boundary) = OlafUploader.makeMultipartBody(reportJSON: reportJSON, screenshot: screenshot)
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(boundary.hasPrefix("OlafBoundary-"))
        XCTAssertTrue(text.contains("name=\"report\""))
        XCTAssertTrue(text.contains("Content-Type: application/json"))
        XCTAssertTrue(text.contains(#"{"hello":"world"}"#))
        XCTAssertTrue(text.contains("name=\"screenshot\"; filename=\"screenshot.jpg\""))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(text.contains("--\(boundary)--"))
    }

    func testMultipartOmitsScreenshotWhenNil() {
        let reportJSON = #"{"a":1}"#.data(using: .utf8)!
        let (body, _) = OlafUploader.makeMultipartBody(reportJSON: reportJSON, screenshot: nil)
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.contains("name=\"report\""))
        XCTAssertFalse(text.contains("name=\"screenshot\""))
    }
}

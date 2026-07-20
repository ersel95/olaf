import XCTest
@testable import Olaf

final class ContentKindTests: XCTestCase {

    private func networkEntry(contentType: String?) -> LogEntry {
        var metadata: [String: String] = ["method": "GET", "url": "https://a.com"]
        if let contentType { metadata["respH.Content-Type"] = contentType }
        return LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: metadata, file: "F.swift", line: 1, function: "f()", thread: "main"
        )
    }

    func testClassification() {
        XCTAssertEqual(NetworkContentKind.of(networkEntry(contentType: "application/json; charset=utf-8")), .json)
        XCTAssertEqual(NetworkContentKind.of(networkEntry(contentType: "image/png")), .image)
        XCTAssertEqual(NetworkContentKind.of(networkEntry(contentType: "text/html")), .html)
        XCTAssertEqual(NetworkContentKind.of(networkEntry(contentType: "application/xml")), .xml)
        XCTAssertEqual(NetworkContentKind.of(networkEntry(contentType: "text/plain")), .text)
        XCTAssertEqual(NetworkContentKind.of(networkEntry(contentType: "application/octet-stream")), .other)
        XCTAssertEqual(NetworkContentKind.of(networkEntry(contentType: nil)), .other)
    }

    func testNonNetworkEntryIsNil() {
        let plain = LogEntry(
            date: Date(), level: .info, category: .general, message: "m",
            metadata: [:], file: "F.swift", line: 1, function: "f()", thread: "main"
        )
        XCTAssertNil(NetworkContentKind.of(plain))
    }

    func testFilterByContentKindHidesNonNetworkAndOtherKinds() {
        let entries = [
            networkEntry(contentType: "application/json"),
            networkEntry(contentType: "image/jpeg"),
            LogEntry(date: Date(), level: .info, category: .general, message: "app",
                     metadata: [:], file: "F.swift", line: 1, function: "f()", thread: "main")
        ]
        let levels = Set(LogLevel.allCases)

        let onlyImages = LogViewerModel.filter(
            entries: entries, query: "", levels: levels, categories: [], contentKinds: [.image]
        )
        XCTAssertEqual(onlyImages.count, 1)
        XCTAssertEqual(NetworkContentKind.of(onlyImages[0]), .image)

        // With the filter off (empty set), no records are hidden.
        let all = LogViewerModel.filter(
            entries: entries, query: "", levels: levels, categories: [], contentKinds: []
        )
        XCTAssertEqual(all.count, 3)
    }

    func testImageBase64RoundtripThroughComposerAndInfo() {
        let pixel = Data([0x89, 0x50, 0x4E, 0x47])   // fake binary content
        var event = NetworkLogEvent(
            method: "GET", url: "https://a.com/logo.png", statusCode: 200, durationMs: 5,
            requestBytes: 0, responseBytes: pixel.count, error: nil,
            requestBody: nil, responseBody: nil
        )
        event.responseHeaders = ["Content-Type": "image/png"]
        event.responseImageBase64 = pixel.base64EncodedString()

        let entry = LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: NetworkLogComposer.metadata(for: event),
            file: "F.swift", line: 1, function: "f()", thread: "main"
        )
        let info = NetworkLogInfo(entry: entry)
        XCTAssertEqual(info?.responseImageData, pixel)
        XCTAssertEqual(NetworkContentKind.of(entry), .image)
    }
}

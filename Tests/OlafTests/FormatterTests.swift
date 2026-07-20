import XCTest
@testable import Olaf

final class FormatterTests: XCTestCase {

    private func makeEntry(
        level: LogLevel = .info,
        category: LogCategory = .auth,
        message: String = "merhaba",
        metadata: [String: String] = ["method": "biometric"]
    ) -> LogEntry {
        LogEntry(
            date: Date(timeIntervalSince1970: 0),
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            file: "Module/Auth/LoginView.swift",
            line: 42,
            function: "login()",
            thread: "main"
        )
    }

    func testPlainTextContainsLevelCategoryAndMessage() {
        let line = PlainTextFormatter().string(from: makeEntry())
        XCTAssertTrue(line.contains("[INFO]"))
        XCTAssertTrue(line.contains("[auth]"))
        XCTAssertTrue(line.contains("merhaba"))
        XCTAssertTrue(line.contains("method=biometric"))
        XCTAssertTrue(line.contains("LoginView.swift:42"))
    }

    func testPlainTextCanOmitMetadataAndSource() {
        let line = PlainTextFormatter(includesMetadata: false, includesSource: false)
            .string(from: makeEntry())
        XCTAssertFalse(line.contains("method=biometric"))
        XCTAssertFalse(line.contains("LoginView.swift"))
    }

    func testJSONFormatterProducesValidJSON() throws {
        let line = JSONLogFormatter().string(from: makeEntry())
        let data = try XCTUnwrap(line.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["message"] as? String, "merhaba")
        XCTAssertEqual(object?["line"] as? Int, 42)
    }

    func testFileNameStripsPath() {
        XCTAssertEqual(makeEntry().fileName, "LoginView.swift")
    }
}

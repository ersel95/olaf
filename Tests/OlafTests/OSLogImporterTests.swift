import XCTest
import OSLog
@testable import Olaf

final class OSLogImporterTests: XCTestCase {

    func testLevelMapping() {
        XCTAssertEqual(Olaf.mapOSLogLevel(.debug), .debug)
        XCTAssertEqual(Olaf.mapOSLogLevel(.info), .info)
        XCTAssertEqual(Olaf.mapOSLogLevel(.notice), .notice)
        XCTAssertEqual(Olaf.mapOSLogLevel(.error), .error)
        XCTAssertEqual(Olaf.mapOSLogLevel(.fault), .critical)   // fault maps to the most severe level
        XCTAssertEqual(Olaf.mapOSLogLevel(.undefined), .info)
    }

    func testImportIsNoOpBeforeStart() async throws {
        // If Olaf.start hasn't been called, there's no store → the importer returns 0 without doing anything.
        // (Valid as long as the global Olaf hasn't been started; the test suite never calls Olaf.start.)
        guard !Olaf.isStarted else { throw XCTSkip("Olaf was already started by another test") }
        let imported = try await Olaf.importOSLogEntries(since: Date().addingTimeInterval(-60))
        XCTAssertEqual(imported, 0)
    }
}

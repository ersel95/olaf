import XCTest
@testable import Olaf

final class PinnedEntriesTests: XCTestCase {

    private func makeEntry(_ message: String) -> LogEntry {
        LogEntry(
            date: Date(), level: .info, category: .general, message: message,
            metadata: [:], file: "F.swift", line: 1, function: "f()", thread: "main"
        )
    }

    func testPinnedSelectionIsNewestFirstAndIgnoresUnknownIDs() {
        let a = makeEntry("a")
        let b = makeEntry("b")
        let c = makeEntry("c")

        let pinned = LogViewerModel.pinned(in: [a, b, c], ids: [a.id, c.id, UUID()])
        XCTAssertEqual(pinned.map(\.message), ["c", "a"])   // newest first, unknown ids are ignored
    }

    func testEmptyIDsShortCircuits() {
        let entries = [makeEntry("a"), makeEntry("b")]
        XCTAssertTrue(LogViewerModel.pinned(in: entries, ids: []).isEmpty)
    }
}

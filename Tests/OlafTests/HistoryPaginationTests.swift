import XCTest
@testable import Olaf

/// History pagination — reading newest to oldest with a file-bounded cursor.
final class HistoryPaginationTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("olaf-paging-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeEntry(_ message: String) -> LogEntry {
        LogEntry(
            date: Date(), level: .info, category: .general, message: message,
            metadata: [:], file: "T.swift", line: 1, function: "f()", thread: "main"
        )
    }

    /// Builds a multi-file history using a small maxFileSize (each write is ~payload-sized).
    private func makeRotatedHistory(entryCount: Int, perFileBytes: Int = 2000) throws -> FilePersistence {
        let persistence = try XCTUnwrap(FilePersistence(
            directory: directory, maxFileSize: perFileBytes, maxFileCount: 100
        ))
        for i in 1...entryCount {
            persistence.write(makeEntry(String(repeating: "x", count: 600) + "#\(i)"))
        }
        return persistence
    }

    func testFirstPageReturnsNewestEntries() throws {
        let persistence = try makeRotatedHistory(entryCount: 12)

        let page = persistence.loadEntriesPage(before: nil, minimumEntries: 3)
        XCTAssertFalse(page.entries.isEmpty)
        XCTAssertNotNil(page.nextCursor)                       // the rest remains
        // The first page should contain the NEWEST entry.
        XCTAssertTrue(page.entries.contains { $0.message.hasSuffix("#12") })
        // Order within the page should be oldest to newest.
        let numbers = page.entries.compactMap { Int($0.message.split(separator: "#").last ?? "") }
        XCTAssertEqual(numbers, numbers.sorted())
    }

    func testCursorWalkCoversAllEntriesExactlyOnce() throws {
        let persistence = try makeRotatedHistory(entryCount: 20)
        let all = persistence.loadEntries()

        var collected: [LogEntry] = []
        var cursor: String?
        var pages = 0
        repeat {
            let page = persistence.loadEntriesPage(before: cursor, minimumEntries: 4)
            collected.insert(contentsOf: page.entries, at: 0)   // prepend, the way the viewer does
            cursor = page.nextCursor
            pages += 1
            XCTAssertLessThan(pages, 100, "cursor isn't advancing (infinite loop)")
        } while cursor != nil

        XCTAssertGreaterThan(pages, 1, "test should have produced multi-file pagination")
        // All entries, in exact order, without duplicates: merged pages == a single read.
        XCTAssertEqual(collected.map(\.id), all.map(\.id))
    }

    func testMinimumEntriesSpansMultipleFiles() throws {
        let persistence = try makeRotatedHistory(entryCount: 12)
        // A single file holds ~2-3 entries; requesting 8 should consume multiple files.
        let page = persistence.loadEntriesPage(before: nil, minimumEntries: 8)
        XCTAssertGreaterThanOrEqual(page.entries.count, 8)
    }

    func testDeletedCursorFileFallsBackToOlderFiles() throws {
        let persistence = try makeRotatedHistory(entryCount: 12)
        let first = persistence.loadEntriesPage(before: nil, minimumEntries: 3)
        let cursor = try XCTUnwrap(first.nextCursor)

        // Simulate the cursor's file having been deleted (prune scenario).
        try FileManager.default.removeItem(at: directory.appendingPathComponent(cursor))

        let second = persistence.loadEntriesPage(before: cursor, minimumEntries: 3)
        // Fallback: continues from older files and doesn't overlap with the first page.
        let firstIDs = Set(first.entries.map(\.id))
        XCTAssertFalse(second.entries.isEmpty)
        XCTAssertTrue(firstIDs.isDisjoint(with: second.entries.map(\.id)))
    }

    func testEmptyStoreReturnsEmptyPageWithoutCursor() throws {
        let persistence = try XCTUnwrap(FilePersistence(
            directory: directory, maxFileSize: 1_048_576, maxFileCount: 5
        ))
        let page = persistence.loadEntriesPage(before: nil, minimumEntries: 100)
        XCTAssertTrue(page.entries.isEmpty)
        XCTAssertNil(page.nextCursor)
    }
}

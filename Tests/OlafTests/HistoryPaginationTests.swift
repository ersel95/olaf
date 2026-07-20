import XCTest
@testable import Olaf

/// Geçmişte sayfalama — dosya-sınırlı imleçle en yeniden geriye okuma.
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

    /// Küçük maxFileSize ile çok dosyalı bir geçmiş kurar (her yazım ~payload boyutunda).
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
        XCTAssertNotNil(page.nextCursor)                       // gerisi duruyor
        // İlk sayfa EN YENİ kaydı içermeli.
        XCTAssertTrue(page.entries.contains { $0.message.hasSuffix("#12") })
        // Sayfa içi sıra eskiden yeniye olmalı.
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
            collected.insert(contentsOf: page.entries, at: 0)   // viewer'ın yaptığı gibi başa ekle
            cursor = page.nextCursor
            pages += 1
            XCTAssertLessThan(pages, 100, "imleç ilerlemiyor (sonsuz döngü)")
        } while cursor != nil

        XCTAssertGreaterThan(pages, 1, "test çok dosyalı sayfalama üretmeliydi")
        // Tüm kayıtlar, tam sırayla, tekrarsız: birleştirilmiş sayfalar == tek seferde okuma.
        XCTAssertEqual(collected.map(\.id), all.map(\.id))
    }

    func testMinimumEntriesSpansMultipleFiles() throws {
        let persistence = try makeRotatedHistory(entryCount: 12)
        // Tek dosyada ~2-3 kayıt var; 8 istemek birden çok dosya tüketmeli.
        let page = persistence.loadEntriesPage(before: nil, minimumEntries: 8)
        XCTAssertGreaterThanOrEqual(page.entries.count, 8)
    }

    func testDeletedCursorFileFallsBackToOlderFiles() throws {
        let persistence = try makeRotatedHistory(entryCount: 12)
        let first = persistence.loadEntriesPage(before: nil, minimumEntries: 3)
        let cursor = try XCTUnwrap(first.nextCursor)

        // İmlecin gösterdiği dosya silinmiş olsun (prune senaryosu).
        try FileManager.default.removeItem(at: directory.appendingPathComponent(cursor))

        let second = persistence.loadEntriesPage(before: cursor, minimumEntries: 3)
        // Düşüş: daha eski dosyalardan devam eder ve ilk sayfayla kesişmez.
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

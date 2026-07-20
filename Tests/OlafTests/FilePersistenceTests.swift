import XCTest
@testable import Olaf

final class FilePersistenceTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("olaf-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeEntry(_ message: String, level: LogLevel = .info) -> LogEntry {
        LogEntry(
            date: Date(),
            level: level,
            category: .general,
            message: message,
            metadata: ["k": "v"],
            file: "Test.swift",
            line: 1,
            function: "f()",
            thread: "main"
        )
    }

    func testWriteThenLoadRoundTrips() throws {
        let persistence = try XCTUnwrap(FilePersistence(directory: directory, maxFileSize: 1_048_576, maxFileCount: 5))
        persistence.write(makeEntry("first"))
        persistence.write(makeEntry("second"))

        let loaded = persistence.loadEntries()
        XCTAssertEqual(loaded.map(\.message), ["first", "second"])
        XCTAssertEqual(loaded.first?.metadata["k"], "v")
    }

    func testPersistsAcrossInstances() throws {
        do {
            let first = try XCTUnwrap(FilePersistence(directory: directory, maxFileSize: 1_048_576, maxFileCount: 5))
            first.write(makeEntry("session-1"))
        }
        // Yeni instance = yeni "oturum"; eski kayıt diskte kalmalı.
        let second = try XCTUnwrap(FilePersistence(directory: directory, maxFileSize: 1_048_576, maxFileCount: 5))
        second.write(makeEntry("session-2"))

        XCTAssertEqual(second.loadEntries().map(\.message), ["session-1", "session-2"])
    }

    func testRotationKeepsRecentAndPrunesOld() throws {
        // Küçük dosya boyutu → her yazımda rotate; maxFileCount=3 → eskiler silinir.
        let persistence = try XCTUnwrap(FilePersistence(directory: directory, maxFileSize: 4096, maxFileCount: 3))
        for i in 1...10 {
            // 4096 byte'ı aşacak büyük mesaj → garanti rotation.
            persistence.write(makeEntry(String(repeating: "x", count: 5000) + "#\(i)"))
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".ndjson") }
        // current + en fazla (maxFileCount-1) rotated = 3 dosya tavanı.
        XCTAssertLessThanOrEqual(files.count, 3)
        // Diskte en az son yazılan kayıt bulunmalı.
        XCTAssertTrue(persistence.loadEntries().contains { $0.message.contains("#10") })
    }

    func testConsolidatedTextURLProducesPlainText() throws {
        let persistence = try XCTUnwrap(FilePersistence(directory: directory, maxFileSize: 1_048_576, maxFileCount: 5))
        persistence.write(makeEntry("readable line", level: .error))

        let url = try XCTUnwrap(persistence.consolidatedTextURL(using: PlainTextFormatter()))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("[ERROR]"))
        XCTAssertTrue(text.contains("readable line"))
        XCTAssertFalse(text.contains("\"message\"")) // JSON değil, düz metin
    }

    func testClearRemovesAllEntries() throws {
        let persistence = try XCTUnwrap(FilePersistence(directory: directory, maxFileSize: 1_048_576, maxFileCount: 5))
        persistence.write(makeEntry("to be cleared"))
        persistence.clear()
        XCTAssertTrue(persistence.loadEntries().isEmpty)
    }

    func testLogEntryCodableRoundTrip() throws {
        let entry = makeEntry("codable", level: .warning)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(LogEntry.self, from: data)
        XCTAssertEqual(decoded.message, "codable")
        XCTAssertEqual(decoded.level, .warning)
        XCTAssertEqual(decoded.category, .general)
        XCTAssertEqual(decoded.metadata["k"], "v")
    }
}

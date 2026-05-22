import XCTest
@testable import LogFoxCore

final class LogStoreTests: XCTestCase {

    private func makeStore(capacity: Int, redactor: any Redactor = NoopRedactor()) -> LogStore {
        LogStore(
            capacity: capacity,
            redactor: redactor,
            persistence: nil,
            exportFormatter: PlainTextFormatter(),
            osLogMirror: nil
        )
    }

    private func ingest(_ store: LogStore, _ message: String, level: LogLevel = .info) {
        store.ingest(
            date: Date(),
            level: level,
            category: .general,
            rawMessage: message,
            rawMetadata: [:],
            file: "Test.swift",
            line: 1,
            function: "test()",
            thread: "main"
        )
    }

    func testStoresAndReturnsSnapshot() {
        let store = makeStore(capacity: 10)
        ingest(store, "a")
        ingest(store, "b")
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.map(\.message), ["a", "b"])
    }

    func testRingBufferEvictsOldestBeyondCapacity() {
        let store = makeStore(capacity: 3)
        for i in 1...5 { ingest(store, "\(i)") }
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertEqual(snapshot.map(\.message), ["3", "4", "5"])
    }

    func testRedactionAppliedBeforeStorage() {
        let store = makeStore(capacity: 10, redactor: BankingRedactor())
        ingest(store, "PAN=4508034012345678")
        let stored = store.snapshot().first?.message ?? ""
        XCTAssertFalse(stored.contains("4508034012345678"))
    }

    func testClearEmptiesBuffer() {
        let store = makeStore(capacity: 10)
        ingest(store, "a")
        store.clear()
        // clear async; snapshot serial kuyrukta sıraya girer → temizlik tamamlanmış olur.
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testStreamReceivesNewEntries() async {
        let store = makeStore(capacity: 10)
        let stream = store.makeStream()

        let received = Task { () -> String? in
            for await entry in stream { return entry.message }
            return nil
        }

        // Aboneliğin kuyruğa kaydı için kısa bekleme.
        try? await Task.sleep(nanoseconds: 50_000_000)
        ingest(store, "live")

        let result = await received.value
        XCTAssertEqual(result, "live")
    }
}

import XCTest
@testable import Olaf

final class LogStoreTests: XCTestCase {

    private func makeStore(capacity: Int) -> LogStore {
        LogStore(
            capacity: capacity,
            persistence: nil,
            exportFormatter: PlainTextFormatter(),
            osLogMirror: nil,
            sessionID: "test-session"
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

    func testRingBufferMultipleWrapsPreserveOrder() {
        // More writes than a multiple of capacity → head should wrap around several times while order is preserved.
        let store = makeStore(capacity: 3)
        for i in 1...8 { ingest(store, "\(i)") }
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.map(\.message), ["6", "7", "8"])
    }

    func testSnapshotAsyncMatchesSnapshot() async {
        let store = makeStore(capacity: 5)
        for i in 1...3 { ingest(store, "\(i)") }
        let async = await store.snapshotAsync()
        XCTAssertEqual(async.map(\.message), ["1", "2", "3"])
    }

    func testRawDataStoredUnchanged() {
        // No masking/filtering: even sensitive-looking data is stored exactly as-is.
        let store = makeStore(capacity: 10)
        ingest(store, "PAN=4508034012345678")
        let stored = store.snapshot().first?.message ?? ""
        XCTAssertEqual(stored, "PAN=4508034012345678")
    }

    func testClearEmptiesBuffer() {
        let store = makeStore(capacity: 10)
        ingest(store, "a")
        store.clear()
        // clear is async; snapshot gets queued on the serial queue → clearing will have completed by then.
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testExportWritesOnlyGivenEntries() async throws {
        // Filtered export: the subset visible in the viewer is passed in → the file should only contain those.
        let store = makeStore(capacity: 10)
        for i in 1...5 { ingest(store, "msg-\(i)") }
        let subset = Array(store.snapshot().prefix(2))   // "msg-1", "msg-2"

        let url = await store.exportFileURL(entries: subset)
        let exported = try XCTUnwrap(url)
        let text = try String(contentsOf: exported, encoding: .utf8)

        XCTAssertTrue(text.contains("msg-1"))
        XCTAssertTrue(text.contains("msg-2"))
        XCTAssertFalse(text.contains("msg-3"))
        XCTAssertFalse(text.contains("msg-5"))
        try? FileManager.default.removeItem(at: exported)
    }

    func testStreamReceivesNewEntries() async {
        let store = makeStore(capacity: 10)
        let stream = store.makeStream()

        let received = Task { () -> String? in
            for await entry in stream { return entry.message }
            return nil
        }

        // A short wait for the subscription to be registered on the queue.
        try? await Task.sleep(nanoseconds: 50_000_000)
        ingest(store, "live")

        let result = await received.value
        XCTAssertEqual(result, "live")
    }
}

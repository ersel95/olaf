import XCTest
@testable import Olaf

private func makeEntry(
    _ message: String,
    level: LogLevel = .info,
    category: LogCategory = .general,
    session: String = "s1",
    date: Date = Date(),
    metadata: [String: String] = [:]
) -> LogEntry {
    LogEntry(
        date: date, level: level, category: category, message: message,
        metadata: metadata, file: "F.swift", line: 1, function: "f()", thread: "main",
        sessionID: session
    )
}

/// `LogViewerModel`'s pure derivation functions (feed memoized @Published values).
final class ViewerDerivationTests: XCTestCase {

    func testFilterIsNewestFirstAndHonorsLevels() {
        let entries = [
            makeEntry("old", level: .debug),
            makeEntry("new", level: .error)
        ]
        let all = LogViewerModel.filter(entries: entries, query: "", levels: Set(LogLevel.allCases), categories: [])
        XCTAssertEqual(all.map(\.message), ["new", "old"])   // newest on top

        let onlyErrors = LogViewerModel.filter(entries: entries, query: "", levels: [.error], categories: [])
        XCTAssertEqual(onlyErrors.map(\.message), ["new"])
    }

    func testFilterQueryMatchesMessageCategoryAndMetadata() {
        let entries = [
            makeEntry("Login successful", category: .auth),
            makeEntry("balance", metadata: ["requestBody": #"{"iban":"AZ21"}"#]),
            makeEntry("unrelated")
        ]
        let levels = Set(LogLevel.allCases)
        XCTAssertEqual(LogViewerModel.filter(entries: entries, query: "login", levels: levels, categories: []).count, 1)
        XCTAssertEqual(LogViewerModel.filter(entries: entries, query: "auth", levels: levels, categories: []).count, 1)
        XCTAssertEqual(LogViewerModel.filter(entries: entries, query: "az21", levels: levels, categories: []).count, 1)
        XCTAssertEqual(LogViewerModel.filter(entries: entries, query: "no-such-match", levels: levels, categories: []).count, 0)
    }

    func testGroupSessionsExcludesCurrentAndSortsNewestSessionFirst() {
        let old = Date(timeIntervalSince1970: 1_000)
        let mid = Date(timeIntervalSince1970: 2_000)
        let entries = [
            makeEntry("a", session: "old-session", date: old),
            makeEntry("b", session: "new-session", date: mid),
            makeEntry("c", session: "current", date: Date())
        ]
        let groups = LogViewerModel.groupSessions(entries, excluding: "current")
        XCTAssertEqual(groups.map(\.id), ["new-session", "old-session"])   // newest session first
        XCTAssertEqual(groups.first?.startDate, mid)
    }

    func testCategoriesAreUniqueAndSorted() {
        let entries = [
            makeEntry("1", category: .network),
            makeEntry("2", category: .auth),
            makeEntry("3", category: .network)
        ]
        XCTAssertEqual(LogViewerModel.categories(in: entries), [.auth, .network])
    }
}

/// NDJSON export — a format identical to the on-disk schema, readable back losslessly.
final class NDJSONExportTests: XCTestCase {

    func testExportedNDJSONRoundtrips() async throws {
        let store = LogStore(
            capacity: 10, persistence: nil, exportFormatter: PlainTextFormatter(),
            osLogMirror: nil, sessionID: "s"
        )
        let entries = [
            makeEntry("first", level: .warning, metadata: ["k": "v"]),
            makeEntry("second", category: .network)
        ]

        let exportedURL = await store.exportNDJSONFileURL(entries: entries)
        let url = try XCTUnwrap(exportedURL)
        XCTAssertEqual(url.pathExtension, "ndjson")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        let decoded = try lines.map { try decoder.decode(LogEntry.self, from: Data($0.utf8)) }

        // Since ISO-8601 has second-level precision, dates aren't compared exactly; identity + content are enough.
        XCTAssertEqual(decoded.map(\.id), entries.map(\.id))
        XCTAssertEqual(decoded.map(\.message), ["first", "second"])
        XCTAssertEqual(decoded.first?.metadata["k"], "v")
        XCTAssertEqual(decoded.first?.level, .warning)
    }
}

/// The collection threshold, adjustable at runtime.
final class RuntimeLevelTests: XCTestCase {

    func testMinimumLevelAdjustableAtRuntime() {
        let runtime = OlafRuntime()
        runtime.start(with: OlafConfiguration(
            minimumLevel: .debug, persistsToDisk: false, mirrorsToOSLog: false
        ))

        if case .drop = runtime.target(for: .trace) {} else { XCTFail("trace should fall below the threshold") }
        if case .store = runtime.target(for: .info) {} else { XCTFail("info should be collected") }

        runtime.minimumLevel = .warning
        XCTAssertEqual(runtime.minimumLevel, .warning)
        if case .drop = runtime.target(for: .info) {} else { XCTFail("info should drop once the threshold is raised") }
        if case .store = runtime.target(for: .error) {} else { XCTFail("error should be collected") }
    }
}

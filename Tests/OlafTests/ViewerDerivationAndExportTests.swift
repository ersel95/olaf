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

/// `LogViewerModel`'in saf türetme fonksiyonları (memoize edilmiş @Published değerleri besler).
final class ViewerDerivationTests: XCTestCase {

    func testFilterIsNewestFirstAndHonorsLevels() {
        let entries = [
            makeEntry("eski", level: .debug),
            makeEntry("yeni", level: .error)
        ]
        let all = LogViewerModel.filter(entries: entries, query: "", levels: Set(LogLevel.allCases), categories: [])
        XCTAssertEqual(all.map(\.message), ["yeni", "eski"])   // en yeni üstte

        let onlyErrors = LogViewerModel.filter(entries: entries, query: "", levels: [.error], categories: [])
        XCTAssertEqual(onlyErrors.map(\.message), ["yeni"])
    }

    func testFilterQueryMatchesMessageCategoryAndMetadata() {
        let entries = [
            makeEntry("Login başarılı", category: .auth),
            makeEntry("bakiye", metadata: ["requestBody": #"{"iban":"AZ21"}"#]),
            makeEntry("alakasız")
        ]
        let levels = Set(LogLevel.allCases)
        XCTAssertEqual(LogViewerModel.filter(entries: entries, query: "login", levels: levels, categories: []).count, 1)
        XCTAssertEqual(LogViewerModel.filter(entries: entries, query: "auth", levels: levels, categories: []).count, 1)
        XCTAssertEqual(LogViewerModel.filter(entries: entries, query: "az21", levels: levels, categories: []).count, 1)
        XCTAssertEqual(LogViewerModel.filter(entries: entries, query: "yok-böyle", levels: levels, categories: []).count, 0)
    }

    func testGroupSessionsExcludesCurrentAndSortsNewestSessionFirst() {
        let old = Date(timeIntervalSince1970: 1_000)
        let mid = Date(timeIntervalSince1970: 2_000)
        let entries = [
            makeEntry("a", session: "eski-oturum", date: old),
            makeEntry("b", session: "yeni-oturum", date: mid),
            makeEntry("c", session: "mevcut", date: Date())
        ]
        let groups = LogViewerModel.groupSessions(entries, excluding: "mevcut")
        XCTAssertEqual(groups.map(\.id), ["yeni-oturum", "eski-oturum"])   // en yeni oturum önce
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

/// NDJSON export — disk şemasıyla birebir aynı, geri okunabilir format.
final class NDJSONExportTests: XCTestCase {

    func testExportedNDJSONRoundtrips() async throws {
        let store = LogStore(
            capacity: 10, persistence: nil, exportFormatter: PlainTextFormatter(),
            osLogMirror: nil, sessionID: "s"
        )
        let entries = [
            makeEntry("ilk", level: .warning, metadata: ["k": "v"]),
            makeEntry("ikinci", category: .network)
        ]

        let exportedURL = await store.exportNDJSONFileURL(entries: entries)
        let url = try XCTUnwrap(exportedURL)
        XCTAssertEqual(url.pathExtension, "ndjson")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        let decoded = try lines.map { try decoder.decode(LogEntry.self, from: Data($0.utf8)) }

        // ISO-8601 saniye hassasiyetinde olduğundan tarih birebir karşılaştırılmaz; kimlik + içerik yeter.
        XCTAssertEqual(decoded.map(\.id), entries.map(\.id))
        XCTAssertEqual(decoded.map(\.message), ["ilk", "ikinci"])
        XCTAssertEqual(decoded.first?.metadata["k"], "v")
        XCTAssertEqual(decoded.first?.level, .warning)
    }
}

/// Runtime'da değiştirilebilir toplama eşiği.
final class RuntimeLevelTests: XCTestCase {

    func testMinimumLevelAdjustableAtRuntime() {
        let runtime = OlafRuntime()
        runtime.start(with: OlafConfiguration(
            minimumLevel: .debug, persistsToDisk: false, mirrorsToOSLog: false
        ))

        if case .drop = runtime.target(for: .trace) {} else { XCTFail("trace eşiğin altında düşmeli") }
        if case .store = runtime.target(for: .info) {} else { XCTFail("info toplanmalı") }

        runtime.minimumLevel = .warning
        XCTAssertEqual(runtime.minimumLevel, .warning)
        if case .drop = runtime.target(for: .info) {} else { XCTFail("eşik yükselince info düşmeli") }
        if case .store = runtime.target(for: .error) {} else { XCTFail("error toplanmalı") }
    }
}

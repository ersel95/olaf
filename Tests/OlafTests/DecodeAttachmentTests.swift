import XCTest
@testable import Olaf

private func makeEntry(
    _ message: String,
    level: LogLevel = .info,
    category: LogCategory = .general,
    date: Date = Date(timeIntervalSince1970: 1_000),
    metadata: [String: String] = [:]
) -> LogEntry {
    LogEntry(
        date: date, level: level, category: category, message: message,
        metadata: metadata, file: "F.swift", line: 1, function: "f()", thread: "main",
        sessionID: "s1"
    )
}

private func networkEntry(
    url: String,
    date: Date = Date(timeIntervalSince1970: 1_000)
) -> LogEntry {
    makeEntry("GET \(url) → 200", category: .network, date: date, metadata: ["url": url, "method": "GET", "status": "200"])
}

private func decodeEntry(
    url: String?,
    date: Date = Date(timeIntervalSince1970: 1_001)
) -> LogEntry {
    var metadata: [String: String] = ["kind": "RequiredField.missing", "key": "iban", "path": "root"]
    if let url { metadata["url"] = url }
    return makeEntry("The data couldn't be read.", level: .error, category: .decoding, date: date, metadata: metadata)
}

/// `DecodeAttachmentIndex.build` + the fold-aware `LogViewerModel.filter`.
final class DecodeAttachmentTests: XCTestCase {

    private let allLevels = Set(LogLevel.allCases)

    func testAttachesDecodeEntriesToNearestNetworkEntrySameEndpoint() {
        let network = networkEntry(url: "https://api.bank.nl/v1/accounts?page=1")
        // Decode reporter absolutizes a bare path — no query, same host+path.
        let decode1 = decodeEntry(url: "https://api.bank.nl/v1/accounts")
        let decode2 = decodeEntry(url: "https://api.bank.nl/v1/accounts", date: Date(timeIntervalSince1970: 1_002))
        let index = DecodeAttachmentIndex.build(from: [network, decode1, decode2])

        XCTAssertEqual(index.errors(for: network).map(\.id), [decode1.id, decode2.id])
        XCTAssertEqual(index.attachedIDs, [decode1.id, decode2.id])
    }

    func testPrefersNearestInTimeAmongRepeatedCalls() {
        let early = networkEntry(url: "https://api.bank.nl/v1/accounts", date: Date(timeIntervalSince1970: 1_000))
        let late = networkEntry(url: "https://api.bank.nl/v1/accounts", date: Date(timeIntervalSince1970: 1_020))
        let decode = decodeEntry(url: "https://api.bank.nl/v1/accounts", date: Date(timeIntervalSince1970: 1_019))
        let index = DecodeAttachmentIndex.build(from: [early, late, decode])

        XCTAssertTrue(index.errors(for: early).isEmpty)
        XCTAssertEqual(index.errors(for: late).map(\.id), [decode.id])
    }

    func testDecodeEntryWithoutURLOrMatchStaysUnattached() {
        let network = networkEntry(url: "https://api.bank.nl/v1/accounts")
        let noURL = decodeEntry(url: nil)
        let otherEndpoint = decodeEntry(url: "https://api.bank.nl/v1/loans")
        let tooLate = decodeEntry(
            url: "https://api.bank.nl/v1/accounts",
            date: Date(timeIntervalSince1970: 1_000 + DecodeAttachmentIndex.attachWindow + 1)
        )
        let index = DecodeAttachmentIndex.build(from: [network, noURL, otherEndpoint, tooLate])

        XCTAssertTrue(index.attachedIDs.isEmpty)
        XCTAssertTrue(index.errors(for: network).isEmpty)
    }

    func testFilterHidesAttachedRowsButKeepsUnattachedOnes() {
        let network = networkEntry(url: "https://api.bank.nl/v1/accounts")
        let attached = decodeEntry(url: "https://api.bank.nl/v1/accounts")
        let orphan = decodeEntry(url: nil, date: Date(timeIntervalSince1970: 1_002))
        let entries = [network, attached, orphan]
        let index = DecodeAttachmentIndex.build(from: entries)

        let visible = LogViewerModel.filter(
            entries: entries, query: "", levels: allLevels, categories: [], decodeIndex: index
        )
        XCTAssertEqual(visible.map(\.id), [orphan.id, network.id])   // newest first, attached hidden
    }

    func testNetworkRowAnswersForItsFoldedErrorsInFilters() {
        let network = networkEntry(url: "https://api.bank.nl/v1/accounts")   // .info level, .network category
        let attached = decodeEntry(url: "https://api.bank.nl/v1/accounts")
        let entries = [network, attached]
        let index = DecodeAttachmentIndex.build(from: entries)

        // Error-level filter: the (info-level) network row stays visible for its folded errors.
        let errorsOnly = LogViewerModel.filter(
            entries: entries, query: "", levels: [.error], categories: [], decodeIndex: index
        )
        XCTAssertEqual(errorsOnly.map(\.id), [network.id])

        // Decoding category chip: same.
        let decodingOnly = LogViewerModel.filter(
            entries: entries, query: "", levels: allLevels, categories: [.decoding], decodeIndex: index
        )
        XCTAssertEqual(decodingOnly.map(\.id), [network.id])

        // Search hitting only the folded entry's metadata surfaces the network row.
        let searched = LogViewerModel.filter(
            entries: entries, query: "iban", levels: allLevels, categories: [], decodeIndex: index
        )
        XCTAssertEqual(searched.map(\.id), [network.id])
    }

    func testEndpointKeyNormalizesQuerySchemeAndTrailingSlash() {
        XCTAssertEqual(DecodeAttachmentIndex.endpointKey("https://h/a/b?x=1"), "h/a/b")
        XCTAssertEqual(DecodeAttachmentIndex.endpointKey("http://h/a/b/"), "h/a/b")
        XCTAssertEqual(DecodeAttachmentIndex.endpointKey("https://h/a/b"), DecodeAttachmentIndex.endpointKey("http://h/a/b/?p=2"))
    }
}

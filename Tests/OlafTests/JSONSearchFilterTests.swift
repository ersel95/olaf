import XCTest
@testable import Olaf

final class JSONSearchFilterTests: XCTestCase {

    private let json = Formatting.prettyJSON("""
    {
      "accountId": "123",
      "overDraftLimit": { "amount": 5000, "currency": "TRY" },
      "owner": { "name": "Jane", "address": { "city": "Ankara" } },
      "tags": ["personal", "overdraft"],
      "status": "active"
    }
    """)

    func testMatchOpeningObjectIncludesWholeBlock() throws {
        let result = try XCTUnwrap(Formatting.searchKeepingJSONBlocks(json, query: "overDraftLimit"))
        XCTAssertTrue(result.contains("\"overDraftLimit\""))
        XCTAssertTrue(result.contains("\"amount\""))
        XCTAssertTrue(result.contains("\"currency\""))
        // Sibling keys outside the matched block stay hidden.
        XCTAssertFalse(result.contains("\"accountId\""))
        XCTAssertFalse(result.contains("\"status\""))
    }

    func testNestedObjectIsIncludedWhenParentMatches() throws {
        let result = try XCTUnwrap(Formatting.searchKeepingJSONBlocks(json, query: "owner"))
        XCTAssertTrue(result.contains("\"name\""))
        XCTAssertTrue(result.contains("\"city\""))
        XCTAssertFalse(result.contains("\"amount\""))
    }

    func testMatchOpeningArrayIncludesWholeBlock() throws {
        let result = try XCTUnwrap(Formatting.searchKeepingJSONBlocks(json, query: "tags"))
        XCTAssertTrue(result.contains("\"personal\""))
        XCTAssertTrue(result.contains("\"overdraft\""))
    }

    func testScalarMatchStaysSingleLine() throws {
        let result = try XCTUnwrap(Formatting.searchKeepingJSONBlocks(json, query: "accountId"))
        XCTAssertTrue(result.contains("\"accountId\""))
        XCTAssertFalse(result.contains("\"overDraftLimit\""))
        XCTAssertEqual(result.split(separator: "\n").count, 1)
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertNotNil(Formatting.searchKeepingJSONBlocks(json, query: "OVERDRAFTLIMIT"))
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(Formatting.searchKeepingJSONBlocks(json, query: "nonexistent"))
    }

    func testDisjointBlocksAreSeparated() throws {
        // "accountId" and "status" are scalar lines far apart → ellipsis in between.
        let result = try XCTUnwrap(Formatting.searchKeepingJSONBlocks(json, query: "\"a"))
        XCTAssertTrue(result.contains("⋯"))
    }

    func testBracketsInsideStringsAreIgnored() throws {
        let tricky = Formatting.prettyJSON("""
        {
          "note": "curly { and square [ inside",
          "block": { "x": 1 }
        }
        """)
        let result = try XCTUnwrap(Formatting.searchKeepingJSONBlocks(tricky, query: "note"))
        // If string brackets were counted, the block would leak into the result.
        XCTAssertFalse(result.contains("\"x\""))
        XCTAssertEqual(result.split(separator: "\n").count, 1)
    }
}

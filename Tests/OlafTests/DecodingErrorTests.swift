import XCTest
@testable import Olaf

final class DecodingErrorTests: XCTestCase {

    private struct User: Decodable {
        struct Account: Decodable { let iban: String }
        let name: String
        let accounts: [Account]
    }

    func testKeyNotFoundProducesFullPath() {
        let json = #"{"name":"a","accounts":[{"iban":"x"},{}]}"#
        do {
            _ = try JSONDecoder().decode(User.self, from: Data(json.utf8))
            XCTFail("decode should have failed")
        } catch {
            let described = DecodingErrorDescriber.describe(error)
            XCTAssertEqual(described.path, "accounts[1].iban")
            XCTAssertTrue(described.detail.contains("iban"))
        }
    }

    func testTypeMismatchProducesPathAndExpectedType() {
        let json = #"{"name":123,"accounts":[]}"#
        do {
            _ = try JSONDecoder().decode(User.self, from: Data(json.utf8))
            XCTFail("decode should have failed")
        } catch {
            let described = DecodingErrorDescriber.describe(error)
            XCTAssertEqual(described.path, "name")
            XCTAssertTrue(described.detail.contains("Type mismatch"))
        }
    }

    func testDataCorrupted() {
        do {
            _ = try JSONDecoder().decode(User.self, from: Data("not-json".utf8))
            XCTFail("decode should have failed")
        } catch {
            let described = DecodingErrorDescriber.describe(error)
            XCTAssertTrue(described.detail.contains("Corrupted data"))
        }
    }

    func testNonDecodingErrorFallsBackToDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "some other error"])
        let described = DecodingErrorDescriber.describe(error)
        XCTAssertNil(described.path)
        XCTAssertEqual(described.detail, "some other error")
    }

    func testOlafDecodingReturnsValueOnSuccessAndRethrows() throws {
        let good = #"{"name":"a","accounts":[{"iban":"x"}]}"#
        let user = try OlafDecoding.decode(User.self, from: Data(good.utf8))
        XCTAssertEqual(user.accounts.first?.iban, "x")

        XCTAssertThrowsError(try OlafDecoding.decode(User.self, from: Data("{}".utf8))) { error in
            XCTAssertTrue(error is DecodingError)   // the error is rethrown as-is
        }
    }
}

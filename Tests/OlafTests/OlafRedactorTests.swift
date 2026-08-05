import XCTest
@testable import Olaf

final class OlafRedactorTests: XCTestCase {

    private let keys = ["password", "otp", "balance", "iban"]

    private func redactor(
        policy: OlafKeyRedactor.UnparsableBodyPolicy = .maskEntirely,
        substrings: Bool = true
    ) -> OlafKeyRedactor {
        OlafKeyRedactor(keys: keys, matchesSubstrings: substrings, unparsableBodyPolicy: policy)
    }

    // MARK: - JSON bodies

    func testMasksMatchingKeysAndKeepsTheRest() {
        let body = #"{"userName":"ersel","password":"hunter2","amount":42}"#
        let out = redactor().redact(body: body, url: nil)

        XCTAssertFalse(out.contains("hunter2"))
        XCTAssertTrue(out.contains("***"))
        XCTAssertTrue(out.contains("ersel"), "non-sensitive fields must stay readable")
        XCTAssertTrue(out.contains("42"))
    }

    func testMasksNestedObjectsAndArrays() {
        let body = """
        {"accounts":[{"iban":"TR12","balance":{"available":100,"blocked":5}},{"iban":"TR34"}]}
        """
        let out = redactor().redact(body: body, url: nil)

        XCTAssertFalse(out.contains("TR12"))
        XCTAssertFalse(out.contains("TR34"))
        XCTAssertFalse(out.contains("100"), "an entire object under a matching key is masked")
        XCTAssertFalse(out.contains("\"blocked\" : 5"))
    }

    func testSubstringMatchingCoversDerivedFieldNames() {
        let body = #"{"availableBalance":100,"otpCode":"123456"}"#
        let out = redactor().redact(body: body, url: nil)

        XCTAssertFalse(out.contains("100"))
        XCTAssertFalse(out.contains("123456"))
    }

    func testExactMatchingIgnoresDerivedNames() {
        let body = #"{"availableBalance":100,"balance":7}"#
        let out = redactor(substrings: false).redact(body: body, url: nil)

        XCTAssertTrue(out.contains("100"), "exact mode must not match availableBalance")
        XCTAssertFalse(out.contains("\"balance\" : 7"))
    }

    func testOutputStaysValidJSON() {
        let body = #"{"password":"x","nested":{"otp":"1"}}"#
        let out = redactor().redact(body: body, url: nil)
        let parsed = try? JSONSerialization.jsonObject(with: Data(out.utf8))

        XCTAssertNotNil(parsed, "the viewer pretty-prints/highlights this, so it must stay parseable")
    }

    // MARK: - Unparsable bodies

    func testUnparsableBodyIsMaskedEntirelyByDefault() {
        // A truncated body (maxBodyLength) is the realistic case: field matching cannot be trusted.
        let truncated = #"{"password":"hunter2","amount":4"#
        XCTAssertEqual(redactor().redact(body: truncated, url: nil), "***")
    }

    func testKeepRawPolicyLeavesUnparsableBodyUntouched() {
        let truncated = #"{"password":"hunter2","amount":4"#
        let out = redactor(policy: .keepRaw).redact(body: truncated, url: nil)
        XCTAssertEqual(out, truncated)
    }

    func testBestEffortPolicyMasksKeyValueLines() {
        let text = "password: hunter2\namount: 42"
        let out = redactor(policy: .bestEffort).redact(body: text, url: nil)

        XCTAssertFalse(out.contains("hunter2"))
        XCTAssertTrue(out.contains("42"))
    }

    func testEmptyKeyListIsANoOp() {
        let body = #"{"password":"hunter2"}"#
        let out = OlafKeyRedactor(keys: []).redact(body: body, url: nil)
        XCTAssertEqual(out, body, "no keys → nothing to mask, body must not be destroyed")
    }

    // MARK: - Form bodies and URLs

    func testMasksFormEncodedBody() {
        let out = redactor().redact(body: "user=ersel&password=hunter2", url: nil)
        XCTAssertEqual(out, "user=ersel&password=***")
    }

    func testMasksQueryStringInURL() {
        let out = redactor().redact(url: "https://api.example.com/login?user=ersel&otp=123456")
        XCTAssertEqual(out, "https://api.example.com/login?user=ersel&otp=***")
    }

    func testURLWithoutQueryIsUntouched() {
        let url = "https://api.example.com/accounts"
        XCTAssertEqual(redactor().redact(url: url), url)
    }

    // MARK: - Headers

    func testMasksSensitiveHeadersByDefault() {
        let r = redactor()
        XCTAssertEqual(r.redact(headerValue: "Bearer abc", name: "Authorization", url: nil), "***")
        XCTAssertEqual(r.redact(headerValue: "sid=1", name: "cookie", url: nil), "***")
        XCTAssertEqual(r.redact(headerValue: "application/json", name: "Content-Type", url: nil), "application/json")
    }

    // MARK: - Composer wiring (the single choke point)

    private func event() -> NetworkLogEvent {
        var event = NetworkLogEvent(
            method: "POST",
            url: "https://api.example.com/transfer?otp=999",
            statusCode: 200,
            durationMs: 12,
            requestBytes: 1,
            responseBytes: 2
        )
        event.requestBody = #"{"password":"hunter2"}"#
        event.responseBody = #"{"balance":5000}"#
        event.requestHeaders = ["Authorization": "Bearer abc", "Accept": "application/json"]
        return event
    }

    func testComposerAppliesRedactorToBodiesHeadersAndURL() {
        let metadata = NetworkLogComposer.metadata(for: event(), redactor: redactor())

        XCTAssertFalse(metadata["requestBody"]?.contains("hunter2") ?? true)
        XCTAssertFalse(metadata["responseBody"]?.contains("5000") ?? true)
        XCTAssertEqual(metadata["reqH.Authorization"], "***")
        XCTAssertEqual(metadata["reqH.Accept"], "application/json")
        XCTAssertFalse(metadata["url"]?.contains("999") ?? true)
    }

    func testComposerWithoutRedactorStoresEverythingRaw() {
        // The default stays raw — this is what non-prod debugging relies on.
        let metadata = NetworkLogComposer.metadata(for: event())

        XCTAssertTrue(metadata["requestBody"]?.contains("hunter2") ?? false)
        XCTAssertTrue(metadata["responseBody"]?.contains("5000") ?? false)
        XCTAssertEqual(metadata["reqH.Authorization"], "Bearer abc")
        XCTAssertTrue(metadata["url"]?.contains("999") ?? false)
    }

    func testMessageURLIsRedacted() {
        let message = NetworkLogComposer.message(for: event(), redactor: redactor())
        XCTAssertFalse(message.contains("999"))
    }

    func testConfigurationDefaultsToNoRedactor() {
        XCTAssertNil(OlafNetworkConfiguration.default.redactor)
    }
}

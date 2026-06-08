import XCTest
@testable import OlafCore

final class RedactionTests: XCTestCase {

    private let redactor = BankingRedactor()

    func testMasksCardNumberKeepingLastFour() {
        let input = "Kart ile ödeme: 4508 0340 1234 5678 onaylandı"
        let output = redactor.redact(input)
        XCTAssertFalse(output.contains("4508 0340 1234 5678"))
        XCTAssertTrue(output.contains("5678"))
        XCTAssertFalse(output.contains("4508"))
    }

    func testMasksCardNumberWithoutSeparators() {
        let output = redactor.redact("PAN=4508034012345678")
        XCTAssertFalse(output.contains("4508034012345678"))
        XCTAssertTrue(output.contains("5678"))
    }

    func testMasksIBAN() {
        let output = redactor.redact("IBAN: AZ21NABZ00000000137010001944 hesabı")
        XCTAssertFalse(output.contains("AZ21NABZ00000000137010001944"))
        XCTAssertTrue(output.contains("AZ21"))
        XCTAssertTrue(output.contains("1944"))
    }

    func testMasksEmail() {
        let output = redactor.redact("Kullanıcı ersel95@gmail.com giriş yaptı")
        XCTAssertFalse(output.contains("ersel95@gmail.com"))
        XCTAssertTrue(output.contains("@gmail.com"))
        XCTAssertTrue(output.contains("e***"))
    }

    func testMasksSensitiveMetadataKeys() {
        let input = [
            "token": "abc123xyz",
            "otp": "483920",
            "password": "hunter2",
            "method": "biometric",
            "Authorization": "Bearer secret"
        ]
        let output = redactor.redact(metadata: input)
        XCTAssertEqual(output["token"], "***")
        XCTAssertEqual(output["otp"], "***")
        XCTAssertEqual(output["password"], "***")
        XCTAssertEqual(output["Authorization"], "***")
        XCTAssertEqual(output["method"], "biometric") // hassas değil → korunur
    }

    func testRedactsPatternsInMetadataValues() {
        let output = redactor.redact(metadata: ["note": "kart 4508034012345678"])
        XCTAssertFalse(output["note"]?.contains("4508034012345678") ?? true)
    }

    func testMasksPrefixedSensitiveHeaderKeys() {
        // OlafNetwork header'ları "reqH.<Name>" / "respH.<Name>" anahtarlarıyla ekler.
        let output = redactor.redact(metadata: [
            "reqH.Authorization": "Bearer secret",
            "respH.Set-Cookie": "sid=abc",
            "reqH.Accept": "application/json"
        ])
        XCTAssertEqual(output["reqH.Authorization"], "***")
        XCTAssertEqual(output["respH.Set-Cookie"], "***")
        XCTAssertEqual(output["reqH.Accept"], "application/json")
    }

    func testNoopRedactorLeavesTextUntouched() {
        let input = "kart 4508034012345678"
        XCTAssertEqual(NoopRedactor().redact(input), input)
    }

    // MARK: - redactionEnabled flag

    func testRedactionDisabledByDefaultLeavesDataUntouched() {
        let config = OlafConfiguration()
        XCTAssertFalse(config.redactionEnabled)
        let input = "kart 4508034012345678"
        XCTAssertEqual(config.effectiveRedactor.redact(input), input)
        XCTAssertTrue(config.effectiveRedactor is NoopRedactor)
    }

    func testRedactionEnabledMasksData() {
        let config = OlafConfiguration(redactionEnabled: true)
        XCTAssertTrue(config.redactionEnabled)
        let output = config.effectiveRedactor.redact("kart 4508034012345678")
        XCTAssertTrue(output.contains("5678"))
        XCTAssertFalse(output.contains("4508034012345678"))
        XCTAssertTrue(config.effectiveRedactor is BankingRedactor)
    }

    func testBankingDefaultEnablesRedaction() {
        XCTAssertTrue(OlafConfiguration.bankingDefault.redactionEnabled)
    }

    // MARK: - JSON gövde (deep recursive) redaksiyonu (C-2)

    func testRedactsTopLevelSensitiveKeysInJSONBody() {
        let body = """
        {"accessToken":"abc123","balance":99999,"username":"erol"}
        """
        let output = redactor.redact(metadata: ["responseBody": body])["responseBody"]!
        XCTAssertFalse(output.contains("abc123"))
        XCTAssertFalse(output.contains("99999"))
        XCTAssertTrue(output.contains("erol"))           // hassas değil → korunur
        XCTAssertTrue(output.contains("***"))
    }

    func testRedactsNestedSensitiveKeysInJSONBody() {
        let body = """
        {"data":{"card":{"pan":"4508034012345678","cvv":"123"},"refreshToken":"rt-xyz"}}
        """
        let output = redactor.redact(metadata: ["requestBody": body])["requestBody"]!
        XCTAssertFalse(output.contains("4508034012345678"))
        XCTAssertFalse(output.contains("rt-xyz"))
        XCTAssertFalse(output.contains("\"123\""))
    }

    func testRedactsSensitiveKeysInsideJSONArray() {
        let body = """
        {"accounts":[{"iban":"AZ21NABZ00000000137010001944","balance":1000},{"iban":"GB29NWBK60161331926819","balance":2000}]}
        """
        let output = redactor.redact(metadata: ["responseBody": body])["responseBody"]!
        XCTAssertFalse(output.contains("AZ21NABZ00000000137010001944"))
        XCTAssertFalse(output.contains("GB29NWBK60161331926819"))
        XCTAssertFalse(output.contains("1000"))
        XCTAssertFalse(output.contains("2000"))
    }

    func testJSONBodyCaseInsensitivePartialKeyMatch() {
        let body = """
        {"AuthOrIzAtIoN":"Bearer x","Card_No":"4508034012345678","userPassword":"hunter2"}
        """
        let output = redactor.redact(metadata: ["requestBody": body])["requestBody"]!
        XCTAssertFalse(output.contains("Bearer x"))
        XCTAssertFalse(output.contains("4508034012345678"))
        XCTAssertFalse(output.contains("hunter2"))
    }

    func testNonJSONBodyFallsBackToValuePatternRedaction() {
        // JSON değil → kart/IBAN/email örüntü redaksiyonu uygulanmaya devam eder.
        let body = "kart 4508034012345678 ile ödeme, mail ersel95@gmail.com"
        let output = redactor.redact(metadata: ["requestBody": body])["requestBody"]!
        XCTAssertFalse(output.contains("4508034012345678"))
        XCTAssertFalse(output.contains("ersel95@gmail.com"))
        XCTAssertTrue(output.contains("5678"))
    }

    func testJSONBodyStringLeavesPatternsRedacted() {
        // JSON yaprak string'leri de örüntü redaksiyonundan geçer.
        let body = """
        {"note":"musteri karti 4508034012345678"}
        """
        let output = redactor.redact(metadata: ["responseBody": body])["responseBody"]!
        XCTAssertFalse(output.contains("4508034012345678"))
    }

    func testScalarValueNotTreatedAsJSON() {
        // Skaler ("42") JSON object/array değil → value-pattern redaksiyonu (değişmez).
        let output = redactor.redact(metadata: ["count": "42"])["count"]
        XCTAssertEqual(output, "42")
    }

    // MARK: - LogEntry redaksiyonu (upload fail-closed yardımcısı, C-3)

    func testRedactEntriesMasksMessageAndMetadata() {
        let entry = LogEntry(
            date: Date(),
            level: .info,
            category: .network,
            message: "ödeme kart 4508034012345678",
            metadata: ["token": "abc", "responseBody": #"{"balance":500}"#],
            file: "F.swift",
            line: 1,
            function: "f()",
            thread: "main"
        )
        let out = redactor.redact(entries: [entry])[0]
        XCTAssertFalse(out.message.contains("4508034012345678"))
        XCTAssertEqual(out.metadata["token"], "***")
        XCTAssertFalse(out.metadata["responseBody"]?.contains("500") ?? true)
        // Hassas olmayan alanlar korunur.
        XCTAssertEqual(out.category, .network)
        XCTAssertEqual(out.id, entry.id)
    }

    func testNoopRedactorEntriesUnchanged() {
        let entry = LogEntry(
            date: Date(), level: .info, category: .general,
            message: "kart 4508034012345678", metadata: ["token": "abc"],
            file: "F", line: 1, function: "f", thread: "main"
        )
        let out = NoopRedactor().redact(entries: [entry])[0]
        XCTAssertEqual(out.message, entry.message)
        XCTAssertEqual(out.metadata["token"], "abc")
    }
}

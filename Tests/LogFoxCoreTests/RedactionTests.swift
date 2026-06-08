import XCTest
@testable import LogFoxCore

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
        // LogFoxNetwork header'ları "reqH.<Name>" / "respH.<Name>" anahtarlarıyla ekler.
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
        let config = LogFoxConfiguration()
        XCTAssertFalse(config.redactionEnabled)
        let input = "kart 4508034012345678"
        XCTAssertEqual(config.effectiveRedactor.redact(input), input)
        XCTAssertTrue(config.effectiveRedactor is NoopRedactor)
    }

    func testRedactionEnabledMasksData() {
        let config = LogFoxConfiguration(redactionEnabled: true)
        XCTAssertTrue(config.redactionEnabled)
        let output = config.effectiveRedactor.redact("kart 4508034012345678")
        XCTAssertTrue(output.contains("5678"))
        XCTAssertFalse(output.contains("4508034012345678"))
        XCTAssertTrue(config.effectiveRedactor is BankingRedactor)
    }

    func testBankingDefaultEnablesRedaction() {
        XCTAssertTrue(LogFoxConfiguration.bankingDefault.redactionEnabled)
    }
}

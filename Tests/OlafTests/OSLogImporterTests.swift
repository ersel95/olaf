import XCTest
import OSLog
@testable import Olaf

final class OSLogImporterTests: XCTestCase {

    func testLevelMapping() {
        XCTAssertEqual(Olaf.mapOSLogLevel(.debug), .debug)
        XCTAssertEqual(Olaf.mapOSLogLevel(.info), .info)
        XCTAssertEqual(Olaf.mapOSLogLevel(.notice), .notice)
        XCTAssertEqual(Olaf.mapOSLogLevel(.error), .error)
        XCTAssertEqual(Olaf.mapOSLogLevel(.fault), .critical)   // fault en ağır seviyeye eşlenir
        XCTAssertEqual(Olaf.mapOSLogLevel(.undefined), .info)
    }

    func testImportIsNoOpBeforeStart() async throws {
        // Olaf.start çağrılmadıysa store yoktur → importer hiçbir şey yapmadan 0 döner.
        // (Global Olaf başlatılmadığı sürece geçerli; test süiti Olaf.start çağırmaz.)
        guard !Olaf.isStarted else { throw XCTSkip("Olaf başka bir test tarafından başlatılmış") }
        let imported = try await Olaf.importOSLogEntries(since: Date().addingTimeInterval(-60))
        XCTAssertEqual(imported, 0)
    }
}

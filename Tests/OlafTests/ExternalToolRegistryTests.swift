import XCTest
@testable import Olaf

private struct StubBridge: ExternalToolBridge {
    let title: String
    var systemImage: String? { nil }
    @MainActor func open() {}
}

final class ExternalToolRegistryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ExternalToolRegistry.shared.removeAll()
    }

    func testRegisterAddsBridge() {
        ExternalToolRegistry.shared.register(StubBridge(title: "DevTool"))
        XCTAssertEqual(ExternalToolRegistry.shared.all.map(\.title), ["DevTool"])
    }

    func testRegisterPreservesOrder() {
        ExternalToolRegistry.shared.register(StubBridge(title: "A"))
        ExternalToolRegistry.shared.register(StubBridge(title: "B"))
        XCTAssertEqual(ExternalToolRegistry.shared.all.map(\.title), ["A", "B"])
    }

    func testRemoveAllEmptiesRegistry() {
        ExternalToolRegistry.shared.register(StubBridge(title: "X"))
        ExternalToolRegistry.shared.removeAll()
        XCTAssertTrue(ExternalToolRegistry.shared.all.isEmpty)
    }
}

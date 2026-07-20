import XCTest
@testable import Olaf

final class MockingTests: XCTestCase {

    override func tearDown() {
        OlafNetwork.removeAllMocks()
        super.tearDown()
    }

    // MARK: - Matching rules

    func testMatchingRules() {
        let anyMethod = OlafMockResponse(urlContains: "/V1/Accounts", json: "{}")
        XCTAssertTrue(anyMethod.matches(URLRequest(url: URL(string: "https://a.com/v1/accounts?x=1")!)))
        XCTAssertFalse(anyMethod.matches(URLRequest(url: URL(string: "https://a.com/v2/cards")!)))

        var postOnly = URLRequest(url: URL(string: "https://a.com/v1/transfer")!)
        postOnly.httpMethod = "POST"
        let postMock = OlafMockResponse(urlContains: "/v1/transfer", method: "post", json: "{}")
        XCTAssertTrue(postMock.matches(postOnly))
        XCTAssertFalse(postMock.matches(URLRequest(url: URL(string: "https://a.com/v1/transfer")!))) // GET

        // The first one added wins.
        OlafNetwork.addMock(OlafMockResponse(urlContains: "/v1", statusCode: 201, json: "{}"))
        OlafNetwork.addMock(OlafMockResponse(urlContains: "/v1", statusCode: 500, json: "{}"))
        let matched = OlafNetwork.mock(for: URLRequest(url: URL(string: "https://a.com/v1/x")!))
        XCTAssertEqual(matched?.statusCode, 201)
    }

    func testCanInitInterceptsMockedURLEvenWhenExcluded() {
        let previous = OlafNetwork.configuration
        defer { OlafNetwork.configuration = previous }
        OlafNetwork.configuration = OlafNetworkConfiguration(excludedURLs: ["mocked.example"])

        let request = URLRequest(url: URL(string: "https://mocked.example/api")!)
        XCTAssertFalse(OlafURLProtocol.canInit(with: request))   // exclude → not captured

        OlafNetwork.addMock(OlafMockResponse(urlContains: "mocked.example", json: "{}"))
        XCTAssertTrue(OlafURLProtocol.canInit(with: request))    // mock takes priority
    }

    // MARK: - End-to-end delivery (via a real URLSession, without hitting the network)

    private func mockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OlafURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testEndToEndMockDelivery() async throws {
        OlafNetwork.addMock(OlafMockResponse(
            urlContains: "mock.olaf-test",
            statusCode: 418,
            json: #"{"mocked":true}"#
        ))

        // A host that doesn't exist: if the mock didn't kick in, the request would fail on the network.
        let url = URL(string: "https://mock.olaf-test/api/v1/accounts")!
        let (data, response) = try await mockedSession().data(from: url)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 418)
        XCTAssertEqual(
            (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"mocked":true}"#)
    }

    func testTransportErrorMockThrowsURLError() async {
        OlafNetwork.addMock(.failure(urlContains: "fail.olaf-test", error: .timedOut))

        do {
            _ = try await mockedSession().data(from: URL(string: "https://fail.olaf-test/x")!)
            XCTFail("a transport error should have been thrown")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    // MARK: - Viewer flow helpers

    func testSuggestedMockPatternIsHostPlusPathWithoutQuery() {
        let entry = LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: ["method": "GET", "url": "https://api.example.com/v1/pay?id=7&x=1"],
            file: "F.swift", line: 1, function: "f()", thread: "main"
        )
        XCTAssertEqual(NetworkLogInfo(entry: entry)?.suggestedMockPattern, "api.example.com/v1/pay")
    }

    func testRemoveMockByID() {
        let first = OlafMockResponse(urlContains: "/a", json: "{}")
        let second = OlafMockResponse(urlContains: "/b", json: "{}")
        OlafNetwork.addMock(first)
        OlafNetwork.addMock(second)
        XCTAssertEqual(OlafNetwork.activeMocks.count, 2)

        OlafNetwork.removeMock(id: first.id)
        XCTAssertEqual(OlafNetwork.activeMocks.map(\.urlContains), ["/b"])

        OlafNetwork.removeMock(id: first.id)   // unknown id is a no-op
        XCTAssertEqual(OlafNetwork.activeMocks.count, 1)
    }

    // MARK: - Logging flag

    func testComposerMarksMockedEvents() {
        var event = NetworkLogEvent(
            method: "GET", url: "https://a.com", statusCode: 200, durationMs: 5,
            requestBytes: 0, responseBytes: 2, error: nil, requestBody: nil, responseBody: "{}"
        )
        event.mocked = true
        XCTAssertEqual(NetworkLogComposer.metadata(for: event)["mocked"], "true")
        XCTAssertTrue(NetworkLogComposer.message(for: event).contains("[mock]"))

        let entry = LogEntry(
            date: Date(), level: .info, category: .network, message: "m",
            metadata: NetworkLogComposer.metadata(for: event),
            file: "F.swift", line: 1, function: "f()", thread: "main"
        )
        XCTAssertEqual(NetworkLogInfo(entry: entry)?.mocked, true)
    }
}

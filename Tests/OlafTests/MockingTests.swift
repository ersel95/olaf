import XCTest
@testable import Olaf

final class MockingTests: XCTestCase {

    override func tearDown() {
        OlafNetwork.removeAllMocks()
        super.tearDown()
    }

    // MARK: - Eşleşme kuralları

    func testMatchingRules() {
        let anyMethod = OlafMockResponse(urlContains: "/V1/Accounts", json: "{}")
        XCTAssertTrue(anyMethod.matches(URLRequest(url: URL(string: "https://a.com/v1/accounts?x=1")!)))
        XCTAssertFalse(anyMethod.matches(URLRequest(url: URL(string: "https://a.com/v2/cards")!)))

        var postOnly = URLRequest(url: URL(string: "https://a.com/v1/transfer")!)
        postOnly.httpMethod = "POST"
        let postMock = OlafMockResponse(urlContains: "/v1/transfer", method: "post", json: "{}")
        XCTAssertTrue(postMock.matches(postOnly))
        XCTAssertFalse(postMock.matches(URLRequest(url: URL(string: "https://a.com/v1/transfer")!))) // GET

        // İlk eklenen kazanır.
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
        XCTAssertFalse(OlafURLProtocol.canInit(with: request))   // exclude → yakalanmaz

        OlafNetwork.addMock(OlafMockResponse(urlContains: "mocked.example", json: "{}"))
        XCTAssertTrue(OlafURLProtocol.canInit(with: request))    // mock önceliklidir
    }

    // MARK: - Uçtan uca teslimat (gerçek URLSession üzerinden, ağa çıkmadan)

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

        // Var olmayan bir host: mock devreye girmezse istek ağda başarısız olurdu.
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
            XCTFail("taşıma hatası fırlatılmalıydı")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    // MARK: - Loglama işareti

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

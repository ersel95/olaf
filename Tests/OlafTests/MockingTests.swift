import XCTest
@testable import Olaf

final class MockingTests: XCTestCase {

    override func tearDown() {
        // Full teardown, templates and scenarios included — `removeAllMocks()` deliberately keeps
        // the library, which would otherwise leak between tests.
        MockRegistry.shared.removeAll()
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

    // MARK: - Variants and endpoint reset

    private func request(_ url: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        return request
    }

    func testSelectingAVariantSwitchesTheServedResponse() {
        let success = OlafMockVariant(name: "Success", payload: OlafMockPayload(statusCode: 200, json: #"{"ok":true}"#))
        let failure = OlafMockVariant(name: "500", payload: OlafMockPayload(statusCode: 500, json: "{}"))
        let endpointID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/v1/pay",
            variants: [success, failure],
            activeVariantID: success.id
        ))

        let target = request("https://api.example.com/v1/pay")
        XCTAssertEqual(OlafNetwork.mock(for: target)?.statusCode, 200)

        OlafNetwork.selectVariant(failure.id, for: endpointID)
        XCTAssertEqual(OlafNetwork.mock(for: target)?.statusCode, 500)

        // Both variants stay saved — switching is not destructive.
        XCTAssertEqual(OlafNetwork.mockEndpoints.first?.variants.map(\.name), ["Success", "500"])
    }

    func testResetEndpointFallsBackToTheRealNetworkAndKeepsVariants() {
        let variant = OlafMockVariant(name: "Empty", payload: OlafMockPayload(json: #"{"items":[]}"#))
        let endpointID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/v1/list",
            variants: [variant],
            activeVariantID: variant.id
        ))
        let target = request("https://api.example.com/v1/list")
        XCTAssertNotNil(OlafNetwork.mock(for: target))

        OlafNetwork.resetEndpoint(id: endpointID)

        XCTAssertNil(OlafNetwork.mock(for: target))
        XCTAssertEqual(OlafNetwork.mockEndpoints.first?.variants.count, 1)
        XCTAssertTrue(OlafNetwork.activeMocks.isEmpty)   // nothing is being served

        // ...and it can be switched straight back on.
        OlafNetwork.selectVariant(variant.id, for: endpointID)
        XCTAssertEqual(OlafNetwork.mock(for: target)?.statusCode, 200)
    }

    func testRemovingTheServedVariantFallsBackToOriginal() {
        let variant = OlafMockVariant(name: "Empty", payload: OlafMockPayload(json: "{}"))
        let endpointID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/v1/x",
            variants: [variant],
            activeVariantID: variant.id
        ))

        OlafNetwork.removeVariant(id: variant.id, from: endpointID)

        XCTAssertNil(OlafNetwork.mock(for: request("https://api.example.com/v1/x")))
        XCTAssertEqual(OlafNetwork.mockEndpoints.first?.activeVariantID, nil)
    }

    func testVariantResetToCapturedRestoresTheOriginalResponse() {
        let captured = OlafMockPayload(statusCode: 200, json: #"{"balance":42}"#)
        var variant = OlafMockVariant(name: "Captured", payload: captured)
        XCTAssertFalse(variant.isModified)

        variant.payload.statusCode = 500
        variant.payload.body = Data("boom".utf8)
        XCTAssertTrue(variant.isModified)

        variant.resetToCaptured()
        XCTAssertFalse(variant.isModified)
        XCTAssertEqual(variant.payload, captured)
    }

    func testUpdateVariantKeepsTheCapturedPayload() {
        let captured = OlafMockPayload(statusCode: 200, json: "{}")
        let variant = OlafMockVariant(name: "Captured", payload: captured)
        let endpointID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/v1/y",
            variants: [variant],
            activeVariantID: variant.id
        ))

        OlafNetwork.updateVariant(id: variant.id, in: endpointID) { variant in
            variant.name = "Renamed"
            variant.payload.statusCode = 503
        }

        let stored = OlafNetwork.mockEndpoints.first?.variants.first
        XCTAssertEqual(stored?.name, "Renamed")
        XCTAssertEqual(stored?.payload.statusCode, 503)
        XCTAssertEqual(stored?.capturedPayload, captured)   // reset still has something to restore
        XCTAssertEqual(stored?.isModified, true)
    }

    // MARK: - Global override

    func testGlobalOverrideAppliesOnlyWhereNoEndpointEntryExists() {
        let templateID = OlafNetwork.addTemplate(
            OlafMockTemplate(name: "All 500", payload: OlafMockPayload(statusCode: 500, json: "{}"))
        )
        OlafNetwork.globalMockTemplateID = templateID

        // No endpoint entry → the global override is served.
        XCTAssertEqual(OlafNetwork.mock(for: request("https://anything.example/x"))?.statusCode, 500)

        // An endpoint with an active variant wins over the global override.
        let variant = OlafMockVariant(name: "OK", payload: OlafMockPayload(statusCode: 200, json: "{}"))
        let endpointID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/v1/ok",
            variants: [variant],
            activeVariantID: variant.id
        ))
        XCTAssertEqual(OlafNetwork.mock(for: request("https://api.example.com/v1/ok"))?.statusCode, 200)

        // An endpoint on Original is a deliberate "leave this alone" — the global override skips it.
        OlafNetwork.resetEndpoint(id: endpointID)
        XCTAssertNil(OlafNetwork.mock(for: request("https://api.example.com/v1/ok")))
        XCTAssertEqual(OlafNetwork.mock(for: request("https://other.example/x"))?.statusCode, 500)
    }

    func testGlobalOverrideRespectsCaptureFiltersUnlikeEndpointMocks() {
        let previous = OlafNetwork.configuration
        defer { OlafNetwork.configuration = previous }
        OlafNetwork.configuration = OlafNetworkConfiguration(excludedURLs: ["telemetry.example"])

        let templateID = OlafNetwork.addTemplate(
            OlafMockTemplate(name: "Offline", payload: .failure(error: .notConnectedToInternet))
        )
        OlafNetwork.globalMockTemplateID = templateID

        // Excluded → the global override must not drag it into capture.
        let excluded = request("https://telemetry.example/beacon")
        XCTAssertFalse(OlafURLProtocol.canInit(with: excluded))

        // An explicit endpoint mock still overrides the filter, as it always has.
        OlafNetwork.addMock(OlafMockResponse(urlContains: "telemetry.example", json: "{}"))
        XCTAssertTrue(OlafURLProtocol.canInit(with: excluded))
    }

    func testRemovingATemplateClearsItAsTheGlobalOverride() {
        let templateID = OlafNetwork.addTemplate(
            OlafMockTemplate(name: "Custom", payload: OlafMockPayload(statusCode: 503, json: "{}"))
        )
        OlafNetwork.globalMockTemplateID = templateID
        XCTAssertEqual(OlafNetwork.mock(for: request("https://a.com/x"))?.statusCode, 503)

        OlafNetwork.removeTemplate(id: templateID)

        XCTAssertNil(OlafNetwork.globalMockTemplateID)
        XCTAssertNil(OlafNetwork.mock(for: request("https://a.com/x")))
    }

    func testBuiltInTemplatesAreAvailableAndUndeletable() {
        let builtIn = OlafNetwork.mockTemplates
        XCTAssertFalse(builtIn.isEmpty)
        XCTAssertTrue(builtIn.allSatisfy(\.isBuiltIn))

        OlafNetwork.removeTemplate(id: builtIn[0].id)
        XCTAssertEqual(OlafNetwork.mockTemplates.count, builtIn.count)
    }

    // MARK: - Scenarios

    func testScenarioCapturesAndRestoresEverySelection() {
        let listEmpty = OlafMockVariant(name: "Empty", payload: OlafMockPayload(json: #"{"items":[]}"#))
        let listFull = OlafMockVariant(name: "Full", payload: OlafMockPayload(json: #"{"items":[1]}"#))
        let listID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/list",
            variants: [listEmpty, listFull],
            activeVariantID: listEmpty.id
        ))
        let payFail = OlafMockVariant(name: "500", payload: OlafMockPayload(statusCode: 500, json: "{}"))
        let payID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/pay",
            variants: [payFail],
            activeVariantID: payFail.id
        ))
        let templateID = OlafNetwork.addTemplate(
            OlafMockTemplate(name: "All 500", payload: OlafMockPayload(statusCode: 500, json: "{}"))
        )
        OlafNetwork.globalMockTemplateID = templateID

        let scenario = OlafNetwork.saveScenario(name: "Empty state")
        XCTAssertEqual(scenario.selections.count, 2)

        // Drift away from it...
        OlafNetwork.selectVariant(listFull.id, for: listID)
        OlafNetwork.resetEndpoint(id: payID)
        OlafNetwork.globalMockTemplateID = nil

        // ...then come back.
        OlafNetwork.applyScenario(id: scenario.id)

        XCTAssertEqual(OlafNetwork.mock(for: request("https://api.example.com/list"))?.body,
                       Data(#"{"items":[]}"#.utf8))
        XCTAssertEqual(OlafNetwork.mock(for: request("https://api.example.com/pay"))?.statusCode, 500)
        XCTAssertEqual(OlafNetwork.globalMockTemplateID, templateID)
    }

    func testApplyingAScenarioResetsEndpointsItDoesNotName() {
        let first = OlafMockVariant(name: "A", payload: OlafMockPayload(statusCode: 201, json: "{}"))
        let firstID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/a", variants: [first], activeVariantID: first.id
        ))
        let scenario = OlafNetwork.saveScenario(name: "Only A")

        // An endpoint that didn't exist when the scenario was saved.
        let second = OlafMockVariant(name: "B", payload: OlafMockPayload(statusCode: 202, json: "{}"))
        let secondID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/b", variants: [second], activeVariantID: second.id
        ))

        OlafNetwork.applyScenario(id: scenario.id)

        XCTAssertEqual(OlafNetwork.mockEndpoints.first { $0.id == firstID }?.activeVariantID, first.id)
        XCTAssertNil(OlafNetwork.mockEndpoints.first { $0.id == secondID }?.activeVariantID)
    }

    func testScenarioFallsBackToOriginalWhenTheVariantWasDeleted() {
        let variant = OlafMockVariant(name: "A", payload: OlafMockPayload(json: "{}"))
        let endpointID = OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/a", variants: [variant], activeVariantID: variant.id
        ))
        let scenario = OlafNetwork.saveScenario(name: "With A")

        OlafNetwork.removeVariant(id: variant.id, from: endpointID)
        OlafNetwork.applyScenario(id: scenario.id)

        XCTAssertNil(OlafNetwork.mockEndpoints.first?.activeVariantID)
        XCTAssertNil(OlafNetwork.mock(for: request("https://api.example.com/a")))
    }

    // MARK: - Bulk reset

    func testResetAllToOriginalKeepsDefinitionsWhileRemoveAllDropsThem() {
        let variant = OlafMockVariant(name: "A", payload: OlafMockPayload(json: "{}"))
        OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/a", variants: [variant], activeVariantID: variant.id
        ))
        OlafNetwork.globalMockTemplateID = OlafNetwork.mockTemplates[0].id

        OlafNetwork.resetAllToOriginal()
        XCTAssertNil(OlafNetwork.globalMockTemplateID)
        XCTAssertEqual(OlafNetwork.mockEndpoints.count, 1)          // kept
        XCTAssertEqual(OlafNetwork.mockEndpoints.first?.variants.count, 1)
        XCTAssertNil(OlafNetwork.mock(for: request("https://api.example.com/a")))

        OlafNetwork.removeAllMocks()
        XCTAssertTrue(OlafNetwork.mockEndpoints.isEmpty)            // gone
        XCTAssertFalse(OlafNetwork.mockTemplates.isEmpty)           // library survives
    }

    // MARK: - Legacy one-shot API

    func testLegacyMockBecomesAnEndpointWithOneActiveVariant() {
        let mock = OlafMockResponse(urlContains: "/v1/legacy", statusCode: 204, json: "{}")
        OlafNetwork.addMock(mock)

        let endpoint = OlafNetwork.mockEndpoints.first
        XCTAssertEqual(endpoint?.id, mock.id)                       // the id handed out still addresses it
        XCTAssertEqual(endpoint?.variants.count, 1)
        XCTAssertEqual(endpoint?.activeVariantID, endpoint?.variants.first?.id)
        XCTAssertEqual(OlafNetwork.activeMocks.map(\.statusCode), [204])

        // Adding a second variant to a legacy-created endpoint works like any other.
        let alternative = OlafMockVariant(name: "500", payload: OlafMockPayload(statusCode: 500, json: "{}"))
        OlafNetwork.addVariant(alternative, to: mock.id)
        XCTAssertEqual(OlafNetwork.mock(for: request("https://a.com/v1/legacy"))?.statusCode, 500)
    }

    func testRemoveMockAcceptsAVariantIDToo() {
        let variant = OlafMockVariant(name: "A", payload: OlafMockPayload(json: "{}"))
        OlafNetwork.addEndpoint(OlafMockEndpoint(
            urlContains: "api.example.com/a", variants: [variant], activeVariantID: variant.id
        ))

        OlafNetwork.removeMock(id: variant.id)

        XCTAssertEqual(OlafNetwork.mockEndpoints.count, 1)          // the endpoint stays
        XCTAssertTrue(OlafNetwork.mockEndpoints.first!.variants.isEmpty)
        XCTAssertNil(OlafNetwork.mock(for: request("https://api.example.com/a")))
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

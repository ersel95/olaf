import Foundation

/// A fake response returned for matching requests **without hitting the network** (response mocking).
///
/// Lets you test edge cases without touching the real backend: error bodies, empty lists,
/// 5xx scenarios, slow responses (`delaySeconds`), or transport errors (`transportError` — e.g.
/// no internet). Mocked requests are logged normally under the `.network` category and
/// marked as "Mock" in the detail view.
///
/// ```swift
/// OlafNetwork.addMock(OlafMockResponse(
///     urlContains: "/v1/accounts",
///     json: #"{"accounts": []}"#
/// ))
/// OlafNetwork.addMock(.failure(urlContains: "/v1/transfer", error: .timedOut, delaySeconds: 3))
/// ```
///
/// This is the **one-shot** form of the API: a single response for a single match rule. Registering
/// one creates an `OlafMockEndpoint` holding a single active variant, so mocks added this way show
/// up in the viewer alongside the ones built there and can be given further variants, switched, or
/// reset to Original. For several saved responses per endpoint, use
/// `OlafNetwork.addEndpoint(_:)` / `addVariant(_:to:)` directly.
///
/// Matching: the URL (lowercase) contains the `urlContains` part and `method` matches
/// (nil = all methods). If multiple mocks match, the **first one added** wins.
/// Capture filters (`includedURLs`/`excludedURLs`) don't affect mocks.
public struct OlafMockResponse: Sendable, Identifiable {

    /// Record identifier (for removing a single mock from the viewer's mock list).
    public let id: UUID

    /// The part the URL must contain (compared lowercase).
    public var urlContains: String
    /// The HTTP method to match (`nil` = all). Compared uppercase.
    public var method: String?
    /// The response itself — status, headers, body, delay, transport error.
    public var payload: OlafMockPayload

    public var statusCode: Int {
        get { payload.statusCode }
        set { payload.statusCode = newValue }
    }
    public var headers: [String: String] {
        get { payload.headers }
        set { payload.headers = newValue }
    }
    public var body: Data {
        get { payload.body }
        set { payload.body = newValue }
    }
    /// The response is delayed by this many seconds (slow network simulation; shows up in the pending requests bar).
    public var delaySeconds: TimeInterval {
        get { payload.delaySeconds }
        set { payload.delaySeconds = max(0, newValue) }
    }
    /// If set, returns a **transport error** instead of an HTTP response (e.g. `.notConnectedToInternet`).
    public var transportError: URLError.Code? {
        get { payload.transportError }
        set { payload.transportError = newValue }
    }

    public init(
        urlContains: String,
        method: String? = nil,
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: Data = Data(),
        delaySeconds: TimeInterval = 0,
        transportError: URLError.Code? = nil
    ) {
        self.init(
            id: UUID(),
            urlContains: urlContains,
            method: method,
            payload: OlafMockPayload(
                statusCode: statusCode,
                headers: headers,
                body: body,
                delaySeconds: delaySeconds,
                transportError: transportError
            )
        )
    }

    /// Shortcut for a mock with a JSON body (`Content-Type: application/json`).
    public init(
        urlContains: String,
        method: String? = nil,
        statusCode: Int = 200,
        json: String,
        delaySeconds: TimeInterval = 0
    ) {
        self.init(
            urlContains: urlContains,
            method: method,
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: Data(json.utf8),
            delaySeconds: delaySeconds
        )
    }

    init(id: UUID, urlContains: String, method: String?, payload: OlafMockPayload) {
        self.id = id
        self.urlContains = urlContains.lowercased()
        self.method = method?.uppercased()
        self.payload = payload
    }

    /// Shortcut for a transport-error mock (no response; throws a URLError).
    public static func failure(
        urlContains: String,
        method: String? = nil,
        error: URLError.Code = .notConnectedToInternet,
        delaySeconds: TimeInterval = 0
    ) -> OlafMockResponse {
        OlafMockResponse(
            urlContains: urlContains,
            method: method,
            delaySeconds: delaySeconds,
            transportError: error
        )
    }

    /// Does this mock match the given request?
    func matches(_ request: URLRequest) -> Bool {
        OlafMockEndpoint.matches(request, urlContains: urlContains, method: method)
    }

    /// The endpoint entry this one-shot mock is stored as: a single variant, active.
    func asEndpoint(variantName: String = "Default") -> OlafMockEndpoint {
        let variant = OlafMockVariant(name: variantName, payload: payload)
        return OlafMockEndpoint(
            id: id,
            urlContains: urlContains,
            method: method,
            variants: [variant],
            activeVariantID: variant.id
        )
    }
}

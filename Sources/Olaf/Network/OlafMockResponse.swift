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
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data
    /// The response is delayed by this many seconds (slow network simulation; shows up in the pending requests bar).
    public var delaySeconds: TimeInterval
    /// If set, returns a **transport error** instead of an HTTP response (e.g. `.notConnectedToInternet`).
    public var transportError: URLError.Code?

    public init(
        urlContains: String,
        method: String? = nil,
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: Data = Data(),
        delaySeconds: TimeInterval = 0,
        transportError: URLError.Code? = nil
    ) {
        self.id = UUID()
        self.urlContains = urlContains.lowercased()
        self.method = method?.uppercased()
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.delaySeconds = max(0, delaySeconds)
        self.transportError = transportError
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
        guard let url = request.url?.absoluteString.lowercased(), url.contains(urlContains) else {
            return false
        }
        guard let method else { return true }
        return method == (request.httpMethod ?? "GET").uppercased()
    }
}

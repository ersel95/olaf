import Foundation

/// The **response half** of a mock: everything except which requests it applies to.
///
/// Splitting it out is what lets the same response be reused in three places — as one of an
/// endpoint's saved variants (`OlafMockVariant`), as a URL-agnostic template
/// (`OlafMockTemplate`), and as the global override applied to every captured request.
public struct OlafMockPayload: Sendable, Equatable {

    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data
    /// The response is delayed by this many seconds (slow network simulation; shows up in the pending requests bar).
    public var delaySeconds: TimeInterval
    /// If set, a **transport error** is produced instead of an HTTP response (e.g. `.notConnectedToInternet`).
    public var transportError: URLError.Code?

    public init(
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: Data = Data(),
        delaySeconds: TimeInterval = 0,
        transportError: URLError.Code? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.delaySeconds = max(0, delaySeconds)
        self.transportError = transportError
    }

    /// Shortcut for a JSON-bodied payload.
    public init(statusCode: Int = 200, json: String, delaySeconds: TimeInterval = 0) {
        self.init(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: Data(json.utf8),
            delaySeconds: delaySeconds
        )
    }

    /// Shortcut for a transport-error payload (no response; a URLError is thrown).
    public static func failure(
        error: URLError.Code = .notConnectedToInternet,
        delaySeconds: TimeInterval = 0
    ) -> OlafMockPayload {
        OlafMockPayload(delaySeconds: delaySeconds, transportError: error)
    }
}

/// A **named, URL-agnostic response** — the reusable half of the mocking model.
///
/// A template can be applied to an endpoint (becoming one of its variants) or activated as the
/// **global override**, in which case every captured request that has no endpoint entry of its own
/// gets this response. Built-in templates cover the cases teams reach for most; anything saved from
/// the mock editor lands here too.
public struct OlafMockTemplate: Sendable, Identifiable, Equatable {

    public let id: UUID
    public var name: String
    public var payload: OlafMockPayload
    /// Built-in templates ship with Olaf and can't be deleted from the viewer.
    public let isBuiltIn: Bool

    public init(name: String, payload: OlafMockPayload) {
        self.id = UUID()
        self.name = name
        self.payload = payload
        self.isBuiltIn = false
    }

    init(id: UUID = UUID(), name: String, payload: OlafMockPayload, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.payload = payload
        self.isBuiltIn = isBuiltIn
    }

    /// The templates every Olaf install starts with.
    public static let builtIn: [OlafMockTemplate] = [
        OlafMockTemplate(
            name: "401 Unauthorized",
            payload: OlafMockPayload(statusCode: 401, json: #"{"error":"unauthorized"}"#),
            isBuiltIn: true
        ),
        OlafMockTemplate(
            name: "404 Not Found",
            payload: OlafMockPayload(statusCode: 404, json: #"{"error":"not_found"}"#),
            isBuiltIn: true
        ),
        OlafMockTemplate(
            name: "500 Server Error",
            payload: OlafMockPayload(statusCode: 500, json: #"{"error":"internal_server_error"}"#),
            isBuiltIn: true
        ),
        OlafMockTemplate(
            name: "Empty list",
            payload: OlafMockPayload(statusCode: 200, json: #"{"items":[]}"#),
            isBuiltIn: true
        ),
        OlafMockTemplate(
            name: "Offline",
            payload: .failure(error: .notConnectedToInternet),
            isBuiltIn: true
        ),
        OlafMockTemplate(
            name: "Timeout",
            payload: .failure(error: .timedOut),
            isBuiltIn: true
        ),
        OlafMockTemplate(
            name: "Slow (3s)",
            payload: OlafMockPayload(statusCode: 200, json: "{}", delaySeconds: 3),
            isBuiltIn: true
        )
    ]
}

import Foundation

/// One saved response for an endpoint, under a name you pick ("Success", "Empty", "500").
///
/// Variants are what make switching cheap: instead of deleting a mock and building another one,
/// you keep every case you've set up on the endpoint and pick which one is live.
public struct OlafMockVariant: Sendable, Identifiable, Equatable {

    public let id: UUID
    public var name: String
    public var payload: OlafMockPayload
    /// The payload as it was first captured — what **"Reset to captured response"** restores after
    /// the body/status has been edited. Untouched by later edits.
    public let capturedPayload: OlafMockPayload

    public init(name: String, payload: OlafMockPayload) {
        self.id = UUID()
        self.name = name
        self.payload = payload
        self.capturedPayload = payload
    }

    /// Has the payload drifted from what was captured? (The editor's Reset button keys off this.)
    public var isModified: Bool { payload != capturedPayload }

    /// Restores the payload the variant was created with.
    public mutating func resetToCaptured() { payload = capturedPayload }
}

/// A mocked endpoint: the match rule (`urlContains` + `method`) plus every variant saved for it.
///
/// `activeVariantID == nil` means **Original** — the request goes to the real backend and the
/// global override is skipped for it. That's the "reset to original" state: the variants stay on
/// the list, ready to be switched back on.
public struct OlafMockEndpoint: Sendable, Identifiable {

    public let id: UUID
    /// The part the URL must contain (compared lowercase).
    public var urlContains: String
    /// The HTTP method to match (`nil` = all). Compared uppercase.
    public var method: String?
    public var variants: [OlafMockVariant]
    /// The variant currently served; `nil` = Original (real network, global override skipped).
    public var activeVariantID: UUID?

    public init(
        urlContains: String,
        method: String? = nil,
        variants: [OlafMockVariant] = [],
        activeVariantID: UUID? = nil
    ) {
        self.init(
            id: UUID(),
            urlContains: urlContains,
            method: method,
            variants: variants,
            activeVariantID: activeVariantID
        )
    }

    init(
        id: UUID,
        urlContains: String,
        method: String?,
        variants: [OlafMockVariant],
        activeVariantID: UUID?
    ) {
        self.id = id
        self.urlContains = urlContains.lowercased()
        self.method = method?.uppercased()
        self.variants = variants
        self.activeVariantID = activeVariantID
    }

    /// The variant currently served, if any.
    public var activeVariant: OlafMockVariant? {
        guard let activeVariantID else { return nil }
        return variants.first { $0.id == activeVariantID }
    }

    /// Does this endpoint's match rule cover the given request?
    func matches(_ request: URLRequest) -> Bool {
        Self.matches(request, urlContains: urlContains, method: method)
    }

    /// Shared matching rule — also used by the legacy `OlafMockResponse` API.
    static func matches(_ request: URLRequest, urlContains: String, method: String?) -> Bool {
        guard let url = request.url?.absoluteString.lowercased(),
              url.contains(urlContains.lowercased()) else { return false }
        guard let method else { return true }
        return method.uppercased() == (request.httpMethod ?? "GET").uppercased()
    }
}

/// A named snapshot of **which variant every endpoint is on**, plus the global override.
///
/// Applying a scenario flips the whole set at once — endpoints the scenario doesn't mention go back
/// to Original. Useful for "new user", "everything fails", "empty state" style walkthroughs.
public struct OlafMockScenario: Sendable, Identifiable {

    public let id: UUID
    public var name: String
    /// endpoint id → selected variant id. Endpoints missing here are reset to Original.
    public var selections: [UUID: UUID]
    /// The template active as the global override when the scenario was saved.
    public var globalTemplateID: UUID?

    public init(name: String, selections: [UUID: UUID], globalTemplateID: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.selections = selections
        self.globalTemplateID = globalTemplateID
    }
}

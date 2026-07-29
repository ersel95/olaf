import Foundation

/// Olaf network capture facade. Captures the app's network requests and logs them to Olaf
/// **raw** (unredacted) under the `.network` category.
///
/// ```swift
/// // To capture all requests (Alamofire/URLSession custom config):
/// OlafNetwork.install(into: sessionConfiguration)
///
/// // To work TOGETHER with another capture tool, chain it:
/// OlafNetwork.install(into: sessionConfiguration, chainingTo: [OtherCaptureProtocol.self])
/// ```
public enum OlafNetwork {

    private static let box = ConfigBox()

    /// Active configuration. Can be set before/after `Olaf.start`.
    public static var configuration: OlafNetworkConfiguration {
        get { box.value }
        set { box.value = newValue }
    }

    /// Additional `URLProtocol` classes to add to Olaf's own (uncaptured) proxy session when it
    /// restarts a request. Used so other capture tools can also capture the traffic.
    public static var chainedProtocolClasses: [AnyClass] {
        get { box.chained }
        set { box.chained = newValue }
    }

    /// Injects the capture protocol into the given `URLSessionConfiguration` and sets the capture
    /// parameters **at init**.
    /// - Parameters:
    ///   - configuration: The session config the protocol will be prepended to.
    ///   - networkConfiguration: Capture filters (body/header capture on by default).
    ///   - chainingTo: Additional `URLProtocol`s the request should pass through after Olaf
    ///     captures it — so another capture tool also sees the same traffic.
    public static func install(
        into configuration: URLSessionConfiguration,
        with networkConfiguration: OlafNetworkConfiguration = .default,
        chainingTo chainedClasses: [AnyClass] = []
    ) {
        self.configuration = networkConfiguration
        self.chainedProtocolClasses = chainedClasses
        // Remove any existing copies, then guarantee we're prepended first (URLProtocol: "first match wins").
        let id = ObjectIdentifier(OlafURLProtocol.self)
        var classes = (configuration.protocolClasses ?? []).filter { ObjectIdentifier($0) != id }
        classes.insert(OlafURLProtocol.self, at: 0)
        configuration.protocolClasses = classes
    }

    /// Registers the protocol for `URLSession.shared` and global requests, and sets the capture parameters at init.
    public static func installGlobally(
        _ networkConfiguration: OlafNetworkConfiguration = .default,
        chainingTo chainedClasses: [AnyClass] = []
    ) {
        self.configuration = networkConfiguration
        self.chainedProtocolClasses = chainedClasses
        URLProtocol.registerClass(OlafURLProtocol.self)
    }

    /// **Easiest setup — WITHOUT touching the host's networking code.**
    /// Swizzles `URLSessionConfiguration.default/.ephemeral` so it's automatically injected into
    /// every session (including Alamofire) + registers globally for the shared session.
    ///
    /// SSL: the proxy session uses **default system validation** (pinning/OS trust is not bypassed);
    /// for custom enterprise CAs use `allowsArbitraryServerTrustForCapture` (non-prod only). For **non-prod debug** use only.
    ///
    /// ```swift
    /// // One line inside OlafManager.initialize() — no need to touch BaseService:
    /// OlafNetwork.startAutomaticCapture()
    /// ```
    public static func startAutomaticCapture(_ networkConfiguration: OlafNetworkConfiguration = .default) {
        self.configuration = networkConfiguration
        URLSessionConfiguration.olafEnableAutomaticInjection()
        URLProtocol.registerClass(OlafURLProtocol.self)
    }

    /// Removes the global registration.
    public static func uninstallGlobally() {
        URLProtocol.unregisterClass(OlafURLProtocol.self)
    }

    /// Protocol class for manual injection.
    public static var protocolClass: AnyClass { OlafURLProtocol.self }

    /// Currently in-flight (not yet completed) captures — oldest first.
    /// The viewer's "Active requests" section polls this periodically; stuck requests show up here.
    public static var pendingRequests: [PendingNetworkRequest] {
        PendingRequestRegistry.shared.snapshot
    }

    // MARK: - Response mocking
    //
    // Three layers, resolved in this order for every captured request:
    //
    //   1. the matching endpoint's active variant  → served, and capture filters are overridden
    //      (an endpoint on **Original** stops resolution here: real network, no global override)
    //   2. the global override template            → served, but only within the capture filters
    //   3. nothing                                 → real network
    //
    // Everything lives in memory and resets on app restart. Non-prod debug only, like the rest of
    // Olaf — should stay under `#if !PROD`.

    private static var registry: MockRegistry { .shared }

    /// Registers a one-shot mock. Matching requests receive this response **without hitting the
    /// network** (capture must be active — `startAutomaticCapture`/`install`). If multiple mocks
    /// match, the first one added wins.
    ///
    /// The mock is stored as an endpoint with a single active variant, so it shows up in the
    /// viewer's mock list and can be given further variants or reset to Original from there.
    public static func addMock(_ mock: OlafMockResponse) {
        registry.addLegacyMock(mock)
    }

    /// Removes a single mock — by endpoint id (as handed out by `OlafMockResponse.id`) or by
    /// variant id. Used by the viewer's mock list.
    public static func removeMock(id: UUID) {
        registry.removeMock(id: id)
    }

    /// Removes every mocked endpoint and switches the global override off (requests go to the real
    /// backend again). The template library and saved scenario names are kept.
    public static func removeAllMocks() {
        registry.removeAllEndpoints()
    }

    /// The responses currently being served, in the one-shot shape. Endpoints sitting on
    /// **Original** are not included — nothing is served for them.
    public static var activeMocks: [OlafMockResponse] {
        registry.activeMocks
    }

    // MARK: Endpoints and variants

    /// Every mocked endpoint, in insertion order — the viewer's mock list.
    public static var mockEndpoints: [OlafMockEndpoint] {
        registry.endpoints
    }

    /// Registers an endpoint with its saved variants; returns its id.
    @discardableResult
    public static func addEndpoint(_ endpoint: OlafMockEndpoint) -> UUID {
        registry.addEndpoint(endpoint)
    }

    /// Removes an endpoint together with all of its variants.
    public static func removeEndpoint(id: UUID) {
        registry.removeEndpoint(id: id)
    }

    /// Saves another variant on an endpoint; `activate` serves it immediately.
    public static func addVariant(_ variant: OlafMockVariant, to endpointID: UUID, activate: Bool = true) {
        registry.addVariant(variant, to: endpointID, activate: activate)
    }

    /// Removes one saved variant. If it was the active one, the endpoint falls back to Original.
    public static func removeVariant(id variantID: UUID, from endpointID: UUID) {
        registry.removeVariant(id: variantID, from: endpointID)
    }

    /// Edits a saved variant in place (name and/or response). `capturedPayload` is left alone, so
    /// "reset to captured response" keeps working after any number of edits.
    public static func updateVariant(
        id variantID: UUID,
        in endpointID: UUID,
        _ mutate: (inout OlafMockVariant) -> Void
    ) {
        registry.updateVariant(id: variantID, in: endpointID, mutate)
    }

    /// Switches which saved variant an endpoint serves; `nil` means **Original**.
    public static func selectVariant(_ variantID: UUID?, for endpointID: UUID) {
        registry.selectVariant(variantID, for: endpointID)
    }

    /// Puts one endpoint back on **Original**: it hits the real backend again and the global
    /// override doesn't apply to it. Its variants are kept and can be switched back on.
    public static func resetEndpoint(id: UUID) {
        registry.selectVariant(nil, for: id)
    }

    /// Puts every endpoint back on Original and switches the global override off. Nothing is
    /// deleted — this is the "back to the real backend, keep my setup" button.
    public static func resetAllToOriginal() {
        registry.resetAllToOriginal()
    }

    // MARK: Templates and the global override

    /// The template library: built-ins plus anything saved from the mock editor.
    public static var mockTemplates: [OlafMockTemplate] {
        registry.templates
    }

    /// Saves a reusable, URL-agnostic response; returns its id.
    @discardableResult
    public static func addTemplate(_ template: OlafMockTemplate) -> UUID {
        registry.addTemplate(template)
    }

    /// Removes a user-saved template (built-ins can't be removed).
    public static func removeTemplate(id: UUID) {
        registry.removeTemplate(id: id)
    }

    /// The template served to **every captured request without an endpoint entry of its own**;
    /// `nil` = off. Unlike endpoint mocks it respects `includedURLs`/`excludedURLs`.
    public static var globalMockTemplateID: UUID? {
        get { registry.globalTemplateID }
        set { registry.globalTemplateID = newValue }
    }

    // MARK: Scenarios

    /// Saved scenarios — named snapshots of every endpoint's selection plus the global override.
    public static var mockScenarios: [OlafMockScenario] {
        registry.scenarios
    }

    /// Saves the current selection of every endpoint under a name.
    @discardableResult
    public static func saveScenario(name: String) -> OlafMockScenario {
        registry.saveScenario(name: name)
    }

    /// Applies a saved scenario. Endpoints the scenario doesn't name go back to Original.
    public static func applyScenario(id: UUID) {
        registry.applyScenario(id: id)
    }

    public static func removeScenario(id: UUID) {
        registry.removeScenario(id: id)
    }

    // MARK: Resolution (internal — used by `OlafURLProtocol`)

    /// How the request resolves against the three mocking layers.
    static func mockResolution(for request: URLRequest) -> MockResolution {
        registry.resolve(request)
    }

    /// The response to serve for this request, if any.
    static func mock(for request: URLRequest) -> OlafMockPayload? {
        registry.resolve(request).payload
    }

    // Internal access (read by URLProtocol's config).
    static var current: OlafNetworkConfiguration { box.value }

    private final class ConfigBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = OlafNetworkConfiguration.default
        private var _chained: [AnyClass] = []

        var value: OlafNetworkConfiguration {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
        var chained: [AnyClass] {
            get { lock.lock(); defer { lock.unlock() }; return _chained }
            set { lock.lock(); _chained = newValue; lock.unlock() }
        }
    }
}

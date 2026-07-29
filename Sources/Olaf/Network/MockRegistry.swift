import Foundation

/// How a request resolves against the mocking layers.
enum MockResolution {
    /// No mocking rule applies — the request goes to the real backend, capture filters decide the rest.
    case none
    /// An endpoint entry matched but is set to **Original**: real network, and the global override
    /// is deliberately skipped ("leave this endpoint alone" must not be undone by a blanket rule).
    case bypass
    /// An endpoint's active variant. Takes priority over capture filters, as endpoint mocks always have.
    case endpoint(OlafMockPayload)
    /// The global override, applied to requests with no endpoint entry of their own. Unlike endpoint
    /// mocks it respects `includedURLs`/`excludedURLs` — otherwise one switch would also mock the
    /// traffic the host explicitly filtered out.
    case global(OlafMockPayload)

    var payload: OlafMockPayload? {
        switch self {
        case .endpoint(let payload), .global(let payload): return payload
        case .none, .bypass: return nil
        }
    }
}

/// In-memory store for everything mock-related: endpoints and their variants, the template library,
/// saved scenarios, and the active global override.
///
/// Nothing here is written to disk — mocks are a debugging aid for the running session and reset on
/// app restart, deliberately (raw bodies would otherwise outlive the process).
///
/// Thread-safe via a single lock; the resolution path runs on every captured request.
final class MockRegistry: @unchecked Sendable {

    static let shared = MockRegistry()

    private let lock = NSLock()
    private var _endpoints: [OlafMockEndpoint] = []
    private var _templates: [OlafMockTemplate] = OlafMockTemplate.builtIn
    private var _scenarios: [OlafMockScenario] = []
    private var _globalTemplateID: UUID?

    // MARK: - Resolution

    func resolve(_ request: URLRequest) -> MockResolution {
        lock.lock()
        defer { lock.unlock() }

        if let endpoint = _endpoints.first(where: { $0.matches(request) }) {
            guard let variant = endpoint.activeVariant else { return .bypass }
            return .endpoint(variant.payload)
        }
        guard let globalTemplateID = _globalTemplateID,
              let template = _templates.first(where: { $0.id == globalTemplateID }) else {
            return .none
        }
        return .global(template.payload)
    }

    // MARK: - Endpoints

    var endpoints: [OlafMockEndpoint] {
        lock.lock(); defer { lock.unlock() }
        return _endpoints
    }

    /// Adds an endpoint entry and returns its id.
    @discardableResult
    func addEndpoint(_ endpoint: OlafMockEndpoint) -> UUID {
        lock.lock(); defer { lock.unlock() }
        _endpoints.append(endpoint)
        return endpoint.id
    }

    func removeEndpoint(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        _endpoints.removeAll { $0.id == id }
        for index in _scenarios.indices {
            _scenarios[index].selections.removeValue(forKey: id)
        }
    }

    func updateEndpoint(id: UUID, _ mutate: (inout OlafMockEndpoint) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard let index = _endpoints.firstIndex(where: { $0.id == id }) else { return }
        mutate(&_endpoints[index])
    }

    /// The endpoint whose match rule covers this request, if one exists.
    func endpoint(matching request: URLRequest) -> OlafMockEndpoint? {
        lock.lock(); defer { lock.unlock() }
        return _endpoints.first { $0.matches(request) }
    }

    /// An existing endpoint with exactly this match rule — used so saving a second variant for the
    /// same URL extends that endpoint instead of creating a duplicate entry that would never win.
    func endpoint(urlContains: String, method: String?) -> OlafMockEndpoint? {
        let pattern = urlContains.lowercased()
        let normalizedMethod = method?.uppercased()
        lock.lock(); defer { lock.unlock() }
        return _endpoints.first { $0.urlContains == pattern && $0.method == normalizedMethod }
    }

    // MARK: - Variants

    /// Adds a variant to an endpoint; `activate` makes it the served response right away.
    func addVariant(_ variant: OlafMockVariant, to endpointID: UUID, activate: Bool = true) {
        updateEndpoint(id: endpointID) { endpoint in
            endpoint.variants.append(variant)
            if activate { endpoint.activeVariantID = variant.id }
        }
    }

    func removeVariant(id variantID: UUID, from endpointID: UUID) {
        updateEndpoint(id: endpointID) { endpoint in
            endpoint.variants.removeAll { $0.id == variantID }
            if endpoint.activeVariantID == variantID { endpoint.activeVariantID = nil }
        }
    }

    func updateVariant(id variantID: UUID, in endpointID: UUID, _ mutate: (inout OlafMockVariant) -> Void) {
        updateEndpoint(id: endpointID) { endpoint in
            guard let index = endpoint.variants.firstIndex(where: { $0.id == variantID }) else { return }
            mutate(&endpoint.variants[index])
        }
    }

    /// Selects which variant an endpoint serves; `nil` resets it to **Original**.
    func selectVariant(_ variantID: UUID?, for endpointID: UUID) {
        updateEndpoint(id: endpointID) { endpoint in
            guard let variantID else {
                endpoint.activeVariantID = nil
                return
            }
            guard endpoint.variants.contains(where: { $0.id == variantID }) else { return }
            endpoint.activeVariantID = variantID
        }
    }

    /// Puts every endpoint back on Original and clears the global override. Definitions are kept.
    func resetAllToOriginal() {
        lock.lock(); defer { lock.unlock() }
        for index in _endpoints.indices {
            _endpoints[index].activeVariantID = nil
        }
        _globalTemplateID = nil
    }

    /// Removes every endpoint entry and switches the global override off, so nothing is served any
    /// more. The template library and scenario names are kept — they cost nothing and are usually
    /// what the user wants to reuse right after clearing.
    func removeAllEndpoints() {
        lock.lock(); defer { lock.unlock() }
        _endpoints = []
        _globalTemplateID = nil
        for index in _scenarios.indices {
            _scenarios[index].selections = [:]
        }
    }

    // MARK: - Templates

    var templates: [OlafMockTemplate] {
        lock.lock(); defer { lock.unlock() }
        return _templates
    }

    @discardableResult
    func addTemplate(_ template: OlafMockTemplate) -> UUID {
        lock.lock(); defer { lock.unlock() }
        _templates.append(template)
        return template.id
    }

    /// Removes a user-saved template. Built-ins are kept; if the removed one was the global
    /// override, the override is cleared.
    func removeTemplate(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard let index = _templates.firstIndex(where: { $0.id == id }), !_templates[index].isBuiltIn else { return }
        _templates.remove(at: index)
        if _globalTemplateID == id { _globalTemplateID = nil }
        for scenarioIndex in _scenarios.indices where _scenarios[scenarioIndex].globalTemplateID == id {
            _scenarios[scenarioIndex].globalTemplateID = nil
        }
    }

    func template(id: UUID) -> OlafMockTemplate? {
        lock.lock(); defer { lock.unlock() }
        return _templates.first { $0.id == id }
    }

    /// The template applied to every captured request without an endpoint entry; `nil` = off.
    var globalTemplateID: UUID? {
        get { lock.lock(); defer { lock.unlock() }; return _globalTemplateID }
        set {
            lock.lock(); defer { lock.unlock() }
            guard let newValue else {
                _globalTemplateID = nil
                return
            }
            guard _templates.contains(where: { $0.id == newValue }) else { return }
            _globalTemplateID = newValue
        }
    }

    // MARK: - Scenarios

    var scenarios: [OlafMockScenario] {
        lock.lock(); defer { lock.unlock() }
        return _scenarios
    }

    @discardableResult
    func addScenario(_ scenario: OlafMockScenario) -> UUID {
        lock.lock(); defer { lock.unlock() }
        _scenarios.append(scenario)
        return scenario.id
    }

    func removeScenario(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        _scenarios.removeAll { $0.id == id }
    }

    /// Saves the current selection of every endpoint (plus the global override) under a name.
    @discardableResult
    func saveScenario(name: String) -> OlafMockScenario {
        lock.lock(); defer { lock.unlock() }
        var selections: [UUID: UUID] = [:]
        for endpoint in _endpoints {
            if let activeVariantID = endpoint.activeVariantID {
                selections[endpoint.id] = activeVariantID
            }
        }
        let scenario = OlafMockScenario(
            name: name,
            selections: selections,
            globalTemplateID: _globalTemplateID
        )
        _scenarios.append(scenario)
        return scenario
    }

    /// Applies a saved scenario: every endpoint it names switches to that variant, every endpoint
    /// it doesn't goes back to Original, and the global override is set to the scenario's.
    func applyScenario(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard let scenario = _scenarios.first(where: { $0.id == id }) else { return }
        for index in _endpoints.indices {
            let selected = scenario.selections[_endpoints[index].id]
            // A variant that has since been deleted falls back to Original rather than to a stale id.
            if let selected, _endpoints[index].variants.contains(where: { $0.id == selected }) {
                _endpoints[index].activeVariantID = selected
            } else {
                _endpoints[index].activeVariantID = nil
            }
        }
        if let globalTemplateID = scenario.globalTemplateID,
           _templates.contains(where: { $0.id == globalTemplateID }) {
            _globalTemplateID = globalTemplateID
        } else {
            _globalTemplateID = nil
        }
    }

    // MARK: - Legacy one-shot API

    /// Backs `OlafNetwork.addMock(_:)`: stores the mock as an endpoint holding one active variant.
    func addLegacyMock(_ mock: OlafMockResponse) {
        addEndpoint(mock.asEndpoint())
    }

    /// Backs `OlafNetwork.removeMock(id:)` — accepts either an endpoint id or a variant id, so ids
    /// handed out by the old API keep working while viewer-built variants can be removed too.
    func removeMock(id: UUID) {
        lock.lock(); defer { lock.unlock() }

        if _endpoints.contains(where: { $0.id == id }) {
            _endpoints.removeAll { $0.id == id }
            for index in _scenarios.indices {
                _scenarios[index].selections.removeValue(forKey: id)
            }
            return
        }
        guard let index = _endpoints.firstIndex(where: { endpoint in
            endpoint.variants.contains { $0.id == id }
        }) else { return }
        _endpoints[index].variants.removeAll { $0.id == id }
        if _endpoints[index].activeVariantID == id {
            _endpoints[index].activeVariantID = nil
        }
    }

    /// Backs `OlafNetwork.activeMocks`: the currently served endpoint responses, flattened into the
    /// one-shot shape. Endpoints on Original are omitted — nothing is being served for them.
    var activeMocks: [OlafMockResponse] {
        lock.lock(); defer { lock.unlock() }
        return _endpoints.compactMap { endpoint in
            guard let variant = endpoint.activeVariant else { return nil }
            return OlafMockResponse(
                id: endpoint.id,
                urlContains: endpoint.urlContains,
                method: endpoint.method,
                payload: variant.payload
            )
        }
    }

    /// Full teardown — used by `removeAllMocks()` and tests.
    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        _endpoints = []
        _scenarios = []
        _templates = OlafMockTemplate.builtIn
        _globalTemplateID = nil
    }
}

package com.olaf.network

import okhttp3.Request

/**
 * In-memory store for everything mock-related: endpoints and their variants, the template library,
 * saved scenarios, and the active global override.
 *
 * Nothing here is written to disk — mocks are a debugging aid for the running session and reset on
 * app restart, deliberately (raw bodies would otherwise outlive the process).
 *
 * Every mutation and read goes through one lock; the resolution path runs on every captured request.
 */
internal object MockRegistry {

    private val lock = Any()
    private var endpointList: List<OlafMockEndpoint> = emptyList()
    private var templateList: List<OlafMockTemplate> = OlafMockTemplate.BuiltIn
    private var scenarioList: List<OlafMockScenario> = emptyList()
    private var activeGlobalTemplateId: String? = null

    // MARK: - Resolution

    fun resolve(request: Request): MockResolution = synchronized(lock) {
        val endpoint = endpointList.firstOrNull { it.matches(request) }
        if (endpoint != null) {
            val variant = endpoint.activeVariant ?: return MockResolution.Bypass
            return MockResolution.Endpoint(variant.payload)
        }
        val globalId = activeGlobalTemplateId ?: return MockResolution.None
        val template = templateList.firstOrNull { it.id == globalId } ?: return MockResolution.None
        return MockResolution.Global(template.payload)
    }

    // MARK: - Endpoints

    val endpoints: List<OlafMockEndpoint> get() = synchronized(lock) { endpointList }

    fun addEndpoint(endpoint: OlafMockEndpoint): String = synchronized(lock) {
        endpointList = endpointList + endpoint
        endpoint.id
    }

    fun removeEndpoint(id: String) = synchronized(lock) {
        endpointList = endpointList.filterNot { it.id == id }
        scenarioList = scenarioList.map { it.copy(selections = it.selections - id) }
    }

    fun updateEndpoint(id: String, mutate: (OlafMockEndpoint) -> OlafMockEndpoint) = synchronized(lock) {
        endpointList = endpointList.map { if (it.id == id) mutate(it) else it }
    }

    /**
     * An existing endpoint with exactly this match rule — used so saving a second variant for the
     * same URL extends that endpoint instead of creating a duplicate entry that would never win.
     */
    fun endpoint(urlContains: String, method: String?): OlafMockEndpoint? = synchronized(lock) {
        val pattern = urlContains.lowercase()
        val normalized = method?.uppercase()
        endpointList.firstOrNull {
            it.urlContains.lowercase() == pattern && it.method?.uppercase() == normalized
        }
    }

    fun endpoint(id: String): OlafMockEndpoint? = synchronized(lock) {
        endpointList.firstOrNull { it.id == id }
    }

    // MARK: - Variants

    /** Adds a variant to an endpoint; [activate] makes it the served response right away. */
    fun addVariant(variant: OlafMockVariant, endpointId: String, activate: Boolean = true) {
        updateEndpoint(endpointId) { endpoint ->
            endpoint.copy(
                variants = endpoint.variants + variant,
                activeVariantId = if (activate) variant.id else endpoint.activeVariantId
            )
        }
    }

    fun removeVariant(variantId: String, endpointId: String) {
        updateEndpoint(endpointId) { endpoint ->
            endpoint.copy(
                variants = endpoint.variants.filterNot { it.id == variantId },
                activeVariantId = endpoint.activeVariantId.takeIf { it != variantId }
            )
        }
    }

    fun updateVariant(variantId: String, endpointId: String, mutate: (OlafMockVariant) -> OlafMockVariant) {
        updateEndpoint(endpointId) { endpoint ->
            endpoint.copy(
                variants = endpoint.variants.map { if (it.id == variantId) mutate(it) else it }
            )
        }
    }

    /** Selects which variant an endpoint serves; `null` resets it to **Original**. */
    fun selectVariant(variantId: String?, endpointId: String) {
        updateEndpoint(endpointId) { endpoint ->
            when {
                variantId == null -> endpoint.copy(activeVariantId = null)
                endpoint.variants.none { it.id == variantId } -> endpoint
                else -> endpoint.copy(activeVariantId = variantId)
            }
        }
    }

    /** Puts every endpoint back on Original and clears the global override. Definitions are kept. */
    fun resetAllToOriginal() = synchronized(lock) {
        endpointList = endpointList.map { it.copy(activeVariantId = null) }
        activeGlobalTemplateId = null
    }

    /**
     * Removes every endpoint entry and switches the global override off, so nothing is served any
     * more. The template library and scenario names are kept — they cost nothing and are usually
     * what the user wants to reuse right after clearing.
     */
    fun removeAllEndpoints() = synchronized(lock) {
        endpointList = emptyList()
        activeGlobalTemplateId = null
        scenarioList = scenarioList.map { it.copy(selections = emptyMap()) }
    }

    // MARK: - Templates

    val templates: List<OlafMockTemplate> get() = synchronized(lock) { templateList }

    fun addTemplate(template: OlafMockTemplate): String = synchronized(lock) {
        templateList = templateList + template
        template.id
    }

    /**
     * Removes a user-saved template. Built-ins are kept; if the removed one was the global
     * override, the override is cleared.
     */
    fun removeTemplate(id: String) = synchronized(lock) {
        val template = templateList.firstOrNull { it.id == id } ?: return
        if (template.isBuiltIn) return
        templateList = templateList.filterNot { it.id == id }
        if (activeGlobalTemplateId == id) activeGlobalTemplateId = null
        scenarioList = scenarioList.map {
            if (it.globalTemplateId == id) it.copy(globalTemplateId = null) else it
        }
    }

    fun template(id: String): OlafMockTemplate? = synchronized(lock) {
        templateList.firstOrNull { it.id == id }
    }

    /** The template applied to every captured request without an endpoint entry; `null` = off. */
    var globalTemplateId: String?
        get() = synchronized(lock) { activeGlobalTemplateId }
        set(value) = synchronized(lock) {
            activeGlobalTemplateId = when {
                value == null -> null
                templateList.none { it.id == value } -> activeGlobalTemplateId
                else -> value
            }
        }

    // MARK: - Scenarios

    val scenarios: List<OlafMockScenario> get() = synchronized(lock) { scenarioList }

    fun addScenario(scenario: OlafMockScenario): String = synchronized(lock) {
        scenarioList = scenarioList + scenario
        scenario.id
    }

    fun removeScenario(id: String) = synchronized(lock) {
        scenarioList = scenarioList.filterNot { it.id == id }
    }

    /** Saves the current selection of every endpoint (plus the global override) under a name. */
    fun saveScenario(name: String): OlafMockScenario = synchronized(lock) {
        val selections = endpointList
            .mapNotNull { endpoint -> endpoint.activeVariantId?.let { endpoint.id to it } }
            .toMap()
        val scenario = OlafMockScenario(
            name = name,
            selections = selections,
            globalTemplateId = activeGlobalTemplateId
        )
        scenarioList = scenarioList + scenario
        scenario
    }

    /**
     * Applies a saved scenario: every endpoint it names switches to that variant, every endpoint it
     * doesn't goes back to Original, and the global override is set to the scenario's.
     */
    fun applyScenario(id: String) = synchronized(lock) {
        val scenario = scenarioList.firstOrNull { it.id == id } ?: return
        endpointList = endpointList.map { endpoint ->
            val selected = scenario.selections[endpoint.id]
            // A variant that has since been deleted falls back to Original rather than a stale id.
            val resolved = selected?.takeIf { candidate -> endpoint.variants.any { it.id == candidate } }
            endpoint.copy(activeVariantId = resolved)
        }
        activeGlobalTemplateId = scenario.globalTemplateId
            ?.takeIf { candidate -> templateList.any { it.id == candidate } }
    }

    // MARK: - Legacy one-shot API

    /** Backs `OlafNetwork.addMock`: stores the mock as an endpoint holding one active variant. */
    fun addLegacyMock(mock: OlafMockResponse) {
        addEndpoint(mock.asEndpoint())
    }

    /**
     * Backs `OlafNetwork.removeMock` — accepts either an endpoint id or a variant id, so ids handed
     * out by the old API keep working while viewer-built variants can be removed too.
     */
    fun removeMock(id: String) = synchronized(lock) {
        if (endpointList.any { it.id == id }) {
            endpointList = endpointList.filterNot { it.id == id }
            scenarioList = scenarioList.map { it.copy(selections = it.selections - id) }
            return
        }
        endpointList = endpointList.map { endpoint ->
            if (endpoint.variants.none { it.id == id }) {
                endpoint
            } else {
                endpoint.copy(
                    variants = endpoint.variants.filterNot { it.id == id },
                    activeVariantId = endpoint.activeVariantId.takeIf { it != id }
                )
            }
        }
    }

    /**
     * Backs `OlafNetwork.activeMocks`: the currently served endpoint responses, flattened into the
     * one-shot shape. Endpoints on Original are omitted — nothing is being served for them.
     */
    val activeMocks: List<OlafMockResponse>
        get() = synchronized(lock) {
            endpointList.mapNotNull { endpoint ->
                val variant = endpoint.activeVariant ?: return@mapNotNull null
                OlafMockResponse(
                    urlContains = endpoint.urlContains,
                    method = endpoint.method,
                    payload = variant.payload,
                    id = endpoint.id
                )
            }
        }

    /** Full teardown — used by tests. */
    fun removeAll() = synchronized(lock) {
        endpointList = emptyList()
        scenarioList = emptyList()
        templateList = OlafMockTemplate.BuiltIn
        activeGlobalTemplateId = null
    }
}

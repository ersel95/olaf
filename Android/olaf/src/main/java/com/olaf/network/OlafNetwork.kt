package com.olaf.network

import okhttp3.EventListener
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.atomic.AtomicReference

/**
 * Olaf's network capture facade. Captures the app's HTTP traffic and logs it **raw** (unredacted)
 * under the configured category.
 *
 * ```kotlin
 * OkHttpClient.Builder()
 *     .installOlaf()          // capture + timing in one line
 *     .build()
 * ```
 *
 * Unlike iOS — where a `URLSessionConfiguration` swizzle can capture every session without
 * touching the app's networking code — OkHttp has no global injection point, so the interceptor
 * has to be added to the client explicitly. That is the same single line Chucker and every other
 * Android inspector requires.
 */
object OlafNetwork {

    private val configurationRef = AtomicReference(OlafNetworkConfiguration.Default)

    /** Active capture configuration. Can be set before or after `Olaf.start`. */
    var configuration: OlafNetworkConfiguration
        get() = configurationRef.get()
        set(value) {
            configurationRef.set(value)
        }

    /**
     * The capture interceptor. Install it as an **application** interceptor so bodies are seen
     * decompressed and a redirect chain is captured as one logical call.
     */
    fun interceptor(): Interceptor = OlafInterceptor()

    /**
     * The event listener factory that produces the timing breakdown (DNS/TCP/TLS/TTFB, protocol,
     * connection reuse). OkHttp permits only one listener per client — if the app already installs
     * its own, keep it and skip this: everything except the timing section keeps working.
     */
    fun eventListenerFactory(): EventListener.Factory = OlafEventListener.Factory

    /** In-flight captures, oldest first. The viewer's "Active requests" bar polls this. */
    val pendingRequests: List<PendingNetworkRequest>
        get() = PendingRequestRegistry.snapshot()

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
    // Olaf — which is what the no-op artifact exists for.

    /**
     * Registers a one-shot mock. Matching requests get this response **without hitting the
     * network**. When several mocks match, the first one added wins.
     *
     * The mock is stored as an endpoint with a single active variant, so it shows up in the
     * viewer's mock list and can be given further variants or reset to Original from there.
     */
    fun addMock(mock: OlafMockResponse) {
        MockRegistry.addLegacyMock(mock)
    }

    /**
     * Removes a single mock — by endpoint id (as handed out by [OlafMockResponse.id]) or by variant
     * id. Used by the viewer's mock list.
     */
    fun removeMock(id: String) {
        MockRegistry.removeMock(id)
    }

    /**
     * Removes every mocked endpoint and switches the global override off, so requests reach the
     * real backend again. The template library and saved scenario names are kept.
     */
    fun removeAllMocks() {
        MockRegistry.removeAllEndpoints()
    }

    /**
     * The responses currently being served, in the one-shot shape. Endpoints sitting on
     * **Original** are not included — nothing is served for them.
     */
    val activeMocks: List<OlafMockResponse> get() = MockRegistry.activeMocks

    // MARK: Endpoints and variants

    /** Every mocked endpoint, in insertion order — the viewer's mock list. */
    val mockEndpoints: List<OlafMockEndpoint> get() = MockRegistry.endpoints

    /** Registers an endpoint with its saved variants; returns its id. */
    fun addEndpoint(endpoint: OlafMockEndpoint): String = MockRegistry.addEndpoint(endpoint)

    /** Removes an endpoint together with all of its variants. */
    fun removeEndpoint(id: String) {
        MockRegistry.removeEndpoint(id)
    }

    /** Saves another variant on an endpoint; [activate] serves it immediately. */
    fun addVariant(variant: OlafMockVariant, endpointId: String, activate: Boolean = true) {
        MockRegistry.addVariant(variant, endpointId, activate)
    }

    /** Removes one saved variant. If it was the active one, the endpoint falls back to Original. */
    fun removeVariant(variantId: String, endpointId: String) {
        MockRegistry.removeVariant(variantId, endpointId)
    }

    /**
     * Edits a saved variant in place (name and/or response). `capturedPayload` is left alone, so
     * "reset to captured response" keeps working after any number of edits.
     */
    fun updateVariant(variantId: String, endpointId: String, mutate: (OlafMockVariant) -> OlafMockVariant) {
        MockRegistry.updateVariant(variantId, endpointId, mutate)
    }

    /** Switches which saved variant an endpoint serves; `null` means **Original**. */
    fun selectVariant(variantId: String?, endpointId: String) {
        MockRegistry.selectVariant(variantId, endpointId)
    }

    /**
     * Puts one endpoint back on **Original**: it hits the real backend again and the global
     * override doesn't apply to it. Its variants are kept and can be switched back on.
     */
    fun resetEndpoint(id: String) {
        MockRegistry.selectVariant(null, id)
    }

    /**
     * Puts every endpoint back on Original and switches the global override off. Nothing is
     * deleted — this is the "back to the real backend, keep my setup" button.
     */
    fun resetAllToOriginal() {
        MockRegistry.resetAllToOriginal()
    }

    // MARK: Templates and the global override

    /** The template library: built-ins plus anything saved from the mock editor. */
    val mockTemplates: List<OlafMockTemplate> get() = MockRegistry.templates

    /** Saves a reusable, URL-agnostic response; returns its id. */
    fun addTemplate(template: OlafMockTemplate): String = MockRegistry.addTemplate(template)

    /** Removes a user-saved template (built-ins can't be removed). */
    fun removeTemplate(id: String) {
        MockRegistry.removeTemplate(id)
    }

    /**
     * The template served to **every captured request without an endpoint entry of its own**;
     * `null` = off. Unlike endpoint mocks it respects the capture filters.
     */
    var globalMockTemplateId: String?
        get() = MockRegistry.globalTemplateId
        set(value) {
            MockRegistry.globalTemplateId = value
        }

    // MARK: Scenarios

    /** Saved scenarios — named snapshots of every endpoint's selection plus the global override. */
    val mockScenarios: List<OlafMockScenario> get() = MockRegistry.scenarios

    /** Saves the current selection of every endpoint under a name. */
    fun saveScenario(name: String): OlafMockScenario = MockRegistry.saveScenario(name)

    /** Applies a saved scenario. Endpoints the scenario doesn't name go back to Original. */
    fun applyScenario(id: String) {
        MockRegistry.applyScenario(id)
    }

    fun removeScenario(id: String) {
        MockRegistry.removeScenario(id)
    }

    // MARK: Resolution (internal — used by the interceptor)

    /** How the request resolves against the three mocking layers. */
    internal fun mockResolution(request: Request): MockResolution = MockRegistry.resolve(request)

    /** The response to serve for this request, if any. */
    internal fun mock(request: Request): OlafMockPayload? = MockRegistry.resolve(request).payloadOrNull
}

/**
 * Installs Olaf capture (and the timing listener) on this client in a single call.
 *
 * @param withTiming set to `false` when the app already installs its own `EventListener.Factory`;
 *   capture, bodies, headers and mocking all keep working, only the timing section is lost.
 */
fun OkHttpClient.Builder.installOlaf(withTiming: Boolean = true): OkHttpClient.Builder {
    addInterceptor(OlafNetwork.interceptor())
    if (withTiming) {
        eventListenerFactory(OlafNetwork.eventListenerFactory())
    }
    return this
}

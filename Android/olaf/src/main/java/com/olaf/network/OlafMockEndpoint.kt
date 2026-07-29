package com.olaf.network

import okhttp3.Request
import java.util.UUID

/**
 * One saved response for an endpoint, under a name you pick ("Success", "Empty", "500").
 *
 * Variants are what make switching cheap: instead of deleting a mock and building another one, you
 * keep every case you've set up on the endpoint and pick which one is live.
 */
data class OlafMockVariant(
    val name: String,
    val payload: OlafMockPayload,
    /**
     * The payload as it was first captured — what **"Reset to captured response"** restores after
     * the body/status has been edited. Left alone by later edits.
     */
    val capturedPayload: OlafMockPayload = payload,
    val id: String = UUID.randomUUID().toString()
) {
    /** Has the payload drifted from what was captured? (The editor's Reset button keys off this.) */
    val isModified: Boolean get() = payload != capturedPayload

    /** A copy serving the response the variant was created with. */
    fun resetToCaptured(): OlafMockVariant = copy(payload = capturedPayload)
}

/**
 * A mocked endpoint: the match rule ([urlContains] + [method]) plus every variant saved for it.
 *
 * `activeVariantId == null` means **Original** — the request goes to the real backend and the
 * global override is skipped for it. That's the "reset to original" state: the variants stay on the
 * list, ready to be switched back on.
 */
data class OlafMockEndpoint(
    /** Fragment the URL must contain; compared lowercase. */
    val urlContains: String,
    /** HTTP method to match (`null` = any). Compared uppercase. */
    val method: String? = null,
    val variants: List<OlafMockVariant> = emptyList(),
    /** The variant currently served; `null` = Original (real network, global override skipped). */
    val activeVariantId: String? = null,
    val id: String = UUID.randomUUID().toString()
) {

    /** The variant currently served, if any. */
    val activeVariant: OlafMockVariant? get() = variants.firstOrNull { it.id == activeVariantId }

    /** Does this endpoint's match rule cover the given request? */
    internal fun matches(request: Request): Boolean = matches(request, urlContains, method)

    companion object {
        /** Shared matching rule — also used by the legacy [OlafMockResponse] API. */
        internal fun matches(request: Request, urlContains: String, method: String?): Boolean {
            if (!request.url.toString().lowercase().contains(urlContains.lowercase())) return false
            val required = method ?: return true
            return required.uppercase() == request.method.uppercase()
        }
    }
}

/**
 * A named snapshot of **which variant every endpoint is on**, plus the global override.
 *
 * Applying a scenario flips the whole set at once — endpoints the scenario doesn't mention go back
 * to Original. Useful for "new user", "everything fails", "empty state" style walkthroughs.
 */
data class OlafMockScenario(
    val name: String,
    /** endpoint id → selected variant id. Endpoints missing here are reset to Original. */
    val selections: Map<String, String>,
    /** The template active as the global override when the scenario was saved. */
    val globalTemplateId: String? = null,
    val id: String = UUID.randomUUID().toString()
)

/** How a request resolves against the mocking layers. */
internal sealed class MockResolution {

    /** No mocking rule applies — the request goes to the real backend. */
    object None : MockResolution()

    /**
     * An endpoint entry matched but is set to **Original**: real network, and the global override
     * is deliberately skipped ("leave this endpoint alone" must not be undone by a blanket rule).
     */
    object Bypass : MockResolution()

    /** An endpoint's active variant. Takes priority over the capture filters, as endpoint mocks always have. */
    data class Endpoint(val payload: OlafMockPayload) : MockResolution()

    /**
     * The global override, applied to requests with no endpoint entry of their own. Unlike endpoint
     * mocks it respects the capture filters — otherwise one switch would also mock the traffic the
     * host explicitly filtered out.
     */
    data class Global(val payload: OlafMockPayload) : MockResolution()

    val payloadOrNull: OlafMockPayload?
        get() = when (this) {
            is Endpoint -> payload
            is Global -> payload
            None, Bypass -> null
        }
}

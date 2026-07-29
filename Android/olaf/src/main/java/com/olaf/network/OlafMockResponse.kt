package com.olaf.network

import okhttp3.Request
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.UUID

/**
 * A fake response returned for matching requests **without hitting the network**.
 *
 * Lets you exercise edge cases without touching the real backend: error bodies, empty lists, 5xx
 * scenarios, slow responses ([delayMillis]) or transport failures ([transportError] — e.g. no
 * connectivity). Mocked calls are still logged normally and flagged as "Mock" in the detail view.
 *
 * ```kotlin
 * OlafNetwork.addMock(OlafMockResponse(urlContains = "/v1/accounts", json = """{"accounts": []}"""))
 * OlafNetwork.addMock(OlafMockResponse.failure("/v1/rates", TransportError.Timeout, delayMillis = 3_000))
 * ```
 *
 * This is the **one-shot** form of the API: a single response for a single match rule. Registering
 * one creates an [OlafMockEndpoint] holding a single active variant, so mocks added this way show
 * up in the viewer next to the ones built there and can be given further variants, switched, or
 * reset to Original. For several saved responses per endpoint use `OlafNetwork.addEndpoint` /
 * `addVariant` directly.
 *
 * Matching: the lowercased URL contains [urlContains] and [method] matches (`null` = any method).
 * When several mocks match, the **first one added** wins. Capture filters don't affect mocks.
 */
data class OlafMockResponse(
    /** Fragment the URL must contain; compared lowercase. */
    val urlContains: String,

    /** HTTP method to match (`null` = all). Compared uppercase. */
    val method: String? = null,

    val statusCode: Int = 200,

    val headers: Map<String, String> = mapOf("Content-Type" to "application/json"),

    val body: ByteArray = ByteArray(0),

    /** Delays the response by this many milliseconds — a slow-network simulation. */
    val delayMillis: Long = 0,

    /** When set, a **transport failure** is thrown instead of returning an HTTP response. */
    val transportError: TransportError? = null,

    /** Identifier used to remove a single mock from the viewer's mock list. */
    val id: String = UUID.randomUUID().toString()
) {

    /** Transport-level failures a mock can simulate. */
    enum class TransportError {
        NotConnectedToInternet,
        Timeout,
        HostNotFound;

        internal val message: String
            get() = when (this) {
                NotConnectedToInternet -> "Not connected to the internet"
                Timeout -> "The request timed out"
                HostNotFound -> "Host could not be resolved"
            }

        internal fun toIOException(): IOException = when (this) {
            NotConnectedToInternet -> IOException(message)
            Timeout -> SocketTimeoutException(message)
            HostNotFound -> UnknownHostException(message)
        }
    }

    /** Convenience constructor for a JSON-bodied mock. */
    constructor(
        urlContains: String,
        json: String,
        method: String? = null,
        statusCode: Int = 200,
        delayMillis: Long = 0
    ) : this(
        urlContains = urlContains,
        method = method,
        statusCode = statusCode,
        headers = mapOf("Content-Type" to "application/json"),
        body = json.toByteArray(),
        delayMillis = delayMillis
    )

    internal constructor(
        urlContains: String,
        method: String?,
        payload: OlafMockPayload,
        id: String
    ) : this(
        urlContains = urlContains,
        method = method,
        statusCode = payload.statusCode,
        headers = payload.headers,
        body = payload.body,
        delayMillis = payload.delayMillis,
        transportError = payload.transportError,
        id = id
    )

    /** The response itself — status, headers, body, delay, transport error. */
    val payload: OlafMockPayload
        get() = OlafMockPayload(statusCode, headers, body, delayMillis, transportError)

    /** Does this mock match the given request? */
    internal fun matches(request: Request): Boolean =
        OlafMockEndpoint.matches(request, urlContains, method)

    /** The endpoint entry this one-shot mock is stored as: a single variant, active. */
    internal fun asEndpoint(variantName: String = "Default"): OlafMockEndpoint {
        val variant = OlafMockVariant(name = variantName, payload = payload)
        return OlafMockEndpoint(
            urlContains = urlContains,
            method = method,
            variants = listOf(variant),
            activeVariantId = variant.id,
            id = id
        )
    }

    // `body` is a ByteArray, so the generated data-class equality would compare references.
    override fun equals(other: Any?): Boolean = this === other || (other is OlafMockResponse && id == other.id)

    override fun hashCode(): Int = id.hashCode()

    companion object {
        /** Shortcut for a transport-failure mock (no response; an IOException is thrown). */
        fun failure(
            urlContains: String,
            error: TransportError = TransportError.NotConnectedToInternet,
            method: String? = null,
            delayMillis: Long = 0
        ): OlafMockResponse = OlafMockResponse(
            urlContains = urlContains,
            method = method,
            delayMillis = delayMillis,
            transportError = error
        )
    }
}

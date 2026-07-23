package com.olaf.network

import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
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

    /** Does this mock match the given request? */
    internal fun matches(request: Request): Boolean {
        if (!request.url.toString().lowercase().contains(urlContains.lowercase())) return false
        val method = method ?: return true
        return method.uppercase() == request.method.uppercase()
    }

    internal fun toResponse(request: Request): Response {
        val contentType = headers.entries
            .firstOrNull { it.key.equals("Content-Type", ignoreCase = true) }
            ?.value
            ?.toMediaTypeOrNull()

        val builder = Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(statusCode)
            .message(statusMessage(statusCode))
            .body(body.toResponseBody(contentType))

        headers.forEach { (name, value) -> builder.header(name, value) }
        return builder.build()
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

        private fun statusMessage(code: Int): String = when (code) {
            200 -> "OK"
            201 -> "Created"
            204 -> "No Content"
            400 -> "Bad Request"
            401 -> "Unauthorized"
            403 -> "Forbidden"
            404 -> "Not Found"
            500 -> "Internal Server Error"
            503 -> "Service Unavailable"
            else -> "Mock"
        }
    }
}

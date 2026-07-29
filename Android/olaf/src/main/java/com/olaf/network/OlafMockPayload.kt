package com.olaf.network

import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import java.util.UUID

/** Alias so payload-level code doesn't have to spell out the enum nested in [OlafMockResponse]. */
typealias OlafTransportError = OlafMockResponse.TransportError

/**
 * The **response half** of a mock: everything except which requests it applies to.
 *
 * Splitting it out is what lets the same response be reused in three places — as one of an
 * endpoint's saved variants ([OlafMockVariant]), as a URL-agnostic template ([OlafMockTemplate]),
 * and as the global override applied to every captured request.
 */
data class OlafMockPayload(
    val statusCode: Int = 200,
    val headers: Map<String, String> = mapOf("Content-Type" to "application/json"),
    val body: ByteArray = ByteArray(0),
    /** Delays the response by this many milliseconds — a slow-network simulation. */
    val delayMillis: Long = 0,
    /** When set, a **transport failure** is thrown instead of returning an HTTP response. */
    val transportError: OlafTransportError? = null
) {

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

    // `body` is a ByteArray, so the generated data-class equality would compare references — and
    // equality is what "has this variant been edited?" is built on.
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is OlafMockPayload) return false
        return statusCode == other.statusCode &&
            headers == other.headers &&
            body.contentEquals(other.body) &&
            delayMillis == other.delayMillis &&
            transportError == other.transportError
    }

    override fun hashCode(): Int {
        var result = statusCode
        result = 31 * result + headers.hashCode()
        result = 31 * result + body.contentHashCode()
        result = 31 * result + delayMillis.hashCode()
        result = 31 * result + (transportError?.hashCode() ?: 0)
        return result
    }

    companion object {
        /** Shortcut for a JSON-bodied payload. */
        fun json(json: String, statusCode: Int = 200, delayMillis: Long = 0): OlafMockPayload =
            OlafMockPayload(
                statusCode = statusCode,
                headers = mapOf("Content-Type" to "application/json"),
                body = json.toByteArray(),
                delayMillis = delayMillis
            )

        /** Shortcut for a transport-failure payload (no response; an IOException is thrown). */
        fun failure(
            error: OlafTransportError = OlafTransportError.NotConnectedToInternet,
            delayMillis: Long = 0
        ): OlafMockPayload = OlafMockPayload(delayMillis = delayMillis, transportError = error)

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

/**
 * A **named, URL-agnostic response** — the reusable half of the mocking model.
 *
 * A template can be applied to an endpoint (becoming one of its variants) or activated as the
 * **global override**, in which case every captured request without an endpoint entry of its own
 * gets this response. [BuiltIn] templates ship with Olaf and can't be deleted from the viewer.
 */
data class OlafMockTemplate(
    val name: String,
    val payload: OlafMockPayload,
    val isBuiltIn: Boolean = false,
    val id: String = UUID.randomUUID().toString()
) {
    companion object {
        /** The templates every Olaf install starts with. */
        val BuiltIn: List<OlafMockTemplate> = listOf(
            OlafMockTemplate("401 Unauthorized", OlafMockPayload.json("""{"error":"unauthorized"}""", 401), isBuiltIn = true),
            OlafMockTemplate("404 Not Found", OlafMockPayload.json("""{"error":"not_found"}""", 404), isBuiltIn = true),
            OlafMockTemplate("500 Server Error", OlafMockPayload.json("""{"error":"internal_server_error"}""", 500), isBuiltIn = true),
            OlafMockTemplate("Empty list", OlafMockPayload.json("""{"items":[]}"""), isBuiltIn = true),
            OlafMockTemplate("Offline", OlafMockPayload.failure(OlafTransportError.NotConnectedToInternet), isBuiltIn = true),
            OlafMockTemplate("Timeout", OlafMockPayload.failure(OlafTransportError.Timeout), isBuiltIn = true),
            OlafMockTemplate("Slow (3s)", OlafMockPayload.json("{}", delayMillis = 3_000), isBuiltIn = true)
        )
    }
}

package com.olaf.network

import com.olaf.LogCategory
import okhttp3.EventListener
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.UUID

/*
 * No-op counterpart of the network capture API. The interceptor is a pure pass-through, so the
 * release client behaves exactly as if Olaf were never installed.
 */

/** No-op stand-in. */
data class OlafNetworkConfiguration(
    val capturesBodies: Boolean = true,
    val capturesHeaders: Boolean = true,
    val maxBodyLength: Int = 8000,
    val maxImageBodyBytes: Int = 262_144,
    val category: LogCategory = LogCategory.Network,
    val includedUrls: List<String> = emptyList(),
    val excludedUrls: List<String> = emptyList(),
    val bodyDecoders: List<BodyDecoder> = emptyList()
) {
    fun shouldCapture(url: String?): Boolean = false

    companion object {
        val Default = OlafNetworkConfiguration()
    }
}

/** No-op stand-in — never invoked, because nothing is captured. */
fun interface BodyDecoder {
    fun decode(bytes: ByteArray, contentType: String?, contentEncoding: String?): String?
}

/** No-op stand-in. */
data class PendingNetworkRequest(
    val id: String = "",
    val method: String = "",
    val url: String = "",
    val startedAtMillis: Long = 0
) {
    val elapsedSeconds: Long get() = 0
}

/** No-op stand-in. */
data class NetworkTimingMetrics(
    val dnsMs: Long? = null,
    val connectMs: Long? = null,
    val tlsMs: Long? = null,
    val ttfbMs: Long? = null,
    val protocolName: String? = null,
    val reusedConnection: Boolean? = null
)

/** No-op stand-in for the response half of a mock. */
data class OlafMockPayload(
    val statusCode: Int = 200,
    val headers: Map<String, String> = mapOf("Content-Type" to "application/json"),
    val body: ByteArray = ByteArray(0),
    val delayMillis: Long = 0,
    val transportError: OlafTransportError? = null
) {

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
        fun json(json: String, statusCode: Int = 200, delayMillis: Long = 0): OlafMockPayload =
            OlafMockPayload(
                statusCode = statusCode,
                body = json.toByteArray(),
                delayMillis = delayMillis
            )

        fun failure(
            error: OlafTransportError = OlafTransportError.NotConnectedToInternet,
            delayMillis: Long = 0
        ): OlafMockPayload = OlafMockPayload(delayMillis = delayMillis, transportError = error)
    }
}

/** No-op stand-in. */
typealias OlafTransportError = OlafMockResponse.TransportError

/** No-op stand-in. The library ships the same names so host code compiles unchanged in release. */
data class OlafMockTemplate(
    val name: String,
    val payload: OlafMockPayload,
    val isBuiltIn: Boolean = false,
    val id: String = UUID.randomUUID().toString()
) {
    companion object {
        val BuiltIn: List<OlafMockTemplate> = emptyList()
    }
}

/** No-op stand-in. */
data class OlafMockVariant(
    val name: String,
    val payload: OlafMockPayload,
    val capturedPayload: OlafMockPayload = payload,
    val id: String = UUID.randomUUID().toString()
) {
    val isModified: Boolean get() = false

    fun resetToCaptured(): OlafMockVariant = this
}

/** No-op stand-in. */
data class OlafMockEndpoint(
    val urlContains: String,
    val method: String? = null,
    val variants: List<OlafMockVariant> = emptyList(),
    val activeVariantId: String? = null,
    val id: String = UUID.randomUUID().toString()
) {
    val activeVariant: OlafMockVariant? get() = null
}

/** No-op stand-in. */
data class OlafMockScenario(
    val name: String,
    val selections: Map<String, String>,
    val globalTemplateId: String? = null,
    val id: String = UUID.randomUUID().toString()
)

/** No-op stand-in. Registering a mock in release does nothing — requests always hit the network. */
data class OlafMockResponse(
    val urlContains: String,
    val method: String? = null,
    val statusCode: Int = 200,
    val headers: Map<String, String> = mapOf("Content-Type" to "application/json"),
    val body: ByteArray = ByteArray(0),
    val delayMillis: Long = 0,
    val transportError: TransportError? = null,
    val id: String = UUID.randomUUID().toString()
) {

    enum class TransportError {
        NotConnectedToInternet,
        Timeout,
        HostNotFound;

        internal fun toIOException(): IOException = when (this) {
            NotConnectedToInternet -> IOException()
            Timeout -> SocketTimeoutException()
            HostNotFound -> UnknownHostException()
        }
    }

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
        body = json.toByteArray(),
        delayMillis = delayMillis
    )

    val payload: OlafMockPayload
        get() = OlafMockPayload(statusCode, headers, body, delayMillis, transportError)

    override fun equals(other: Any?): Boolean = this === other || (other is OlafMockResponse && id == other.id)

    override fun hashCode(): Int = id.hashCode()

    companion object {
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

/** No-op stand-in. */
object OlafNetwork {

    var configuration: OlafNetworkConfiguration = OlafNetworkConfiguration.Default

    /** A pass-through interceptor: the chain proceeds untouched. */
    fun interceptor(): Interceptor = Interceptor { chain -> chain.proceed(chain.request()) }

    fun eventListenerFactory(): EventListener.Factory = EventListener.Factory { EventListener.NONE }

    val pendingRequests: List<PendingNetworkRequest> get() = emptyList()

    fun addMock(mock: OlafMockResponse) = Unit

    fun removeMock(id: String) = Unit

    fun removeAllMocks() = Unit

    val activeMocks: List<OlafMockResponse> get() = emptyList()

    val mockEndpoints: List<OlafMockEndpoint> get() = emptyList()

    fun addEndpoint(endpoint: OlafMockEndpoint): String = endpoint.id

    fun removeEndpoint(id: String) = Unit

    fun addVariant(variant: OlafMockVariant, endpointId: String, activate: Boolean = true) = Unit

    fun removeVariant(variantId: String, endpointId: String) = Unit

    fun updateVariant(variantId: String, endpointId: String, mutate: (OlafMockVariant) -> OlafMockVariant) = Unit

    fun selectVariant(variantId: String?, endpointId: String) = Unit

    fun resetEndpoint(id: String) = Unit

    fun resetAllToOriginal() = Unit

    val mockTemplates: List<OlafMockTemplate> get() = emptyList()

    fun addTemplate(template: OlafMockTemplate): String = template.id

    fun removeTemplate(id: String) = Unit

    var globalMockTemplateId: String? = null

    val mockScenarios: List<OlafMockScenario> get() = emptyList()

    fun saveScenario(name: String): OlafMockScenario = OlafMockScenario(name, emptyMap())

    fun applyScenario(id: String) = Unit

    fun removeScenario(id: String) = Unit

    internal fun mock(request: Request): OlafMockPayload? = null
}

/**
 * No-op stand-in. Deliberately leaves the client untouched — not even a pass-through interceptor
 * is added, so there is zero overhead in release.
 */
fun OkHttpClient.Builder.installOlaf(withTiming: Boolean = true): OkHttpClient.Builder = this

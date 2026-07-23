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

    internal fun mock(request: Request): OlafMockResponse? = null
}

/**
 * No-op stand-in. Deliberately leaves the client untouched — not even a pass-through interceptor
 * is added, so there is zero overhead in release.
 */
fun OkHttpClient.Builder.installOlaf(withTiming: Boolean = true): OkHttpClient.Builder = this

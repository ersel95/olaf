package com.olaf.network

import okhttp3.EventListener
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.CopyOnWriteArrayList
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
    private val mocks = CopyOnWriteArrayList<OlafMockResponse>()

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

    /**
     * Registers a mock. Matching requests get this response **without hitting the network**. When
     * several mocks match, the first one added wins. Non-prod debug only, like the rest of Olaf.
     */
    fun addMock(mock: OlafMockResponse) {
        mocks.add(mock)
    }

    /** Removes a single mock — used by the viewer's mock list. */
    fun removeMock(id: String) {
        mocks.removeAll { it.id == id }
    }

    /** Removes every mock, so requests reach the real backend again. */
    fun removeAllMocks() {
        mocks.clear()
    }

    /** Registered mocks, in insertion order. */
    val activeMocks: List<OlafMockResponse> get() = mocks.toList()

    /** The first mock matching the request, if any. */
    internal fun mock(request: Request): OlafMockResponse? = mocks.firstOrNull { it.matches(request) }
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

package com.olaf.network

import okhttp3.Call
import okhttp3.Connection
import okhttp3.EventListener
import okhttp3.Handshake
import okhttp3.Protocol
import okhttp3.Response
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.ConcurrentHashMap

/**
 * Collects the phase-by-phase timing OkHttp reports (DNS, TCP connect, TLS, TTFB, protocol,
 * connection reuse) — the Android counterpart of iOS's `URLSessionTaskMetrics`.
 *
 * ### One listener per client
 * OkHttp allows a single `EventListener.Factory` per client, so unlike interceptors this cannot be
 * chained. If your app already installs its own event listener, keep it and skip Olaf's: capture,
 * bodies, headers and mocking all keep working — only the timing breakdown is unavailable.
 */
internal class OlafEventListener : EventListener() {

    private var dnsStart = 0L
    private var dnsEnd = 0L
    private var connectStart = 0L
    private var connectEnd = 0L
    private var tlsStart = 0L
    private var tlsEnd = 0L
    private var requestStart = 0L
    private var responseStart = 0L
    private var protocolName: String? = null

    /** No `connectStart` means OkHttp served the call from the connection pool. */
    private var openedConnection = false

    override fun callStart(call: Call) {
        requestStart = System.nanoTime()
    }

    override fun dnsStart(call: Call, domainName: String) {
        dnsStart = System.nanoTime()
    }

    override fun dnsEnd(call: Call, domainName: String, inetAddressList: List<InetAddress>) {
        dnsEnd = System.nanoTime()
    }

    override fun connectStart(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy) {
        openedConnection = true
        connectStart = System.nanoTime()
    }

    override fun secureConnectStart(call: Call) {
        tlsStart = System.nanoTime()
    }

    override fun secureConnectEnd(call: Call, handshake: Handshake?) {
        tlsEnd = System.nanoTime()
    }

    override fun connectEnd(
        call: Call,
        inetSocketAddress: InetSocketAddress,
        proxy: Proxy,
        protocol: Protocol?
    ) {
        connectEnd = System.nanoTime()
        protocol?.let { protocolName = it.toString() }
    }

    override fun connectionAcquired(call: Call, connection: Connection) {
        protocolName = connection.protocol().toString()
    }

    override fun requestHeadersStart(call: Call) {
        // The send phase starts here; TTFB is measured from this point.
        requestStart = System.nanoTime()
    }

    override fun responseHeadersStart(call: Call) {
        responseStart = System.nanoTime()
    }

    override fun responseHeadersEnd(call: Call, response: Response) {
        // Everything the timing breakdown needs is known by now — the interceptor reads it as soon
        // as `chain.proceed()` returns, which happens right after this callback.
        TimingRegistry.put(call, snapshot())
    }

    override fun callEnd(call: Call) {
        TimingRegistry.put(call, snapshot())
    }

    override fun callFailed(call: Call, ioe: IOException) {
        TimingRegistry.put(call, snapshot())
    }

    private fun snapshot() = NetworkTimingMetrics(
        dnsMs = elapsedMs(dnsStart, dnsEnd),
        connectMs = elapsedMs(connectStart, connectEnd),
        tlsMs = elapsedMs(tlsStart, tlsEnd),
        ttfbMs = elapsedMs(requestStart, responseStart),
        protocolName = protocolName,
        reusedConnection = !openedConnection
    )

    private fun elapsedMs(startNanos: Long, endNanos: Long): Long? =
        if (startNanos == 0L || endNanos == 0L || endNanos < startNanos) null
        else (endNanos - startNanos) / 1_000_000

    /** Hands timing from the listener to the interceptor, keyed by the in-flight [Call]. */
    internal object TimingRegistry {

        private val metrics = ConcurrentHashMap<Call, NetworkTimingMetrics>()

        fun put(call: Call, value: NetworkTimingMetrics) {
            metrics[call] = value
        }

        /** Reads and removes the entry, so a call never leaks past its own lifetime. */
        fun take(call: Call): NetworkTimingMetrics? = metrics.remove(call)

        fun clear() = metrics.clear()
    }

    object Factory : EventListener.Factory {
        override fun create(call: Call): EventListener = OlafEventListener()
    }
}

package com.olaf.network

import com.olaf.LogLevel

/** Raw data of a network event — logged as-is, with no redaction or filtering. */
internal data class NetworkLogEvent(
    val method: String,
    val url: String,
    val statusCode: Int? = null,
    val durationMs: Long = 0,
    val requestBytes: Long = 0,
    val responseBytes: Long = 0,
    val error: String? = null,
    var requestBody: String? = null,
    var responseBody: String? = null,
    var requestHeaders: Map<String, String>? = null,
    var responseHeaders: Map<String, String>? = null,
    /**
     * The call was cancelled before completing (screen dismissed, prefetch abandoned). Not a real
     * failure: logged at INFO with an empty `error` field.
     */
    val cancelled: Boolean = false,
    /** Phase-by-phase timing, `null` when it couldn't be collected. */
    val timing: NetworkTimingMetrics? = null,
    /** Image response body as base64 — only for images under the configured limit. */
    val responseImageBase64: String? = null,
    /** The response came from a mock, so no network call was made. */
    val mocked: Boolean = false
)

/**
 * A request's phase-by-phase timing — answers "is the API slow, or the network?".
 * DNS/connect/TLS are naturally absent on a reused connection.
 */
data class NetworkTimingMetrics(
    val dnsMs: Long? = null,
    val connectMs: Long? = null,
    val tlsMs: Long? = null,
    /** Request sent → first byte of the response (time to first byte). */
    val ttfbMs: Long? = null,
    /** Protocol in use, e.g. `h2`, `http/1.1`. */
    val protocolName: String? = null,
    /** Was a pooled connection reused (no fresh handshake)? */
    val reusedConnection: Boolean? = null
)

/**
 * Turns a network event into level + message + metadata. Pure functions, so it is directly
 * testable — and the metadata keys match the iOS package exactly, which is what lets the viewer
 * (and any external tooling) read either platform's records.
 */
internal object NetworkLogComposer {

    fun level(statusCode: Int?, error: String?, cancelled: Boolean = false): LogLevel = when {
        cancelled -> LogLevel.INFO
        error != null -> LogLevel.ERROR
        statusCode == null -> LogLevel.INFO
        statusCode >= 500 -> LogLevel.ERROR
        statusCode >= 400 -> LogLevel.WARNING
        else -> LogLevel.INFO
    }

    fun message(event: NetworkLogEvent): String = buildList {
        add(event.method)
        add(event.url)
        event.statusCode?.let { add("→ $it") }
        if (event.cancelled) add("→ cancelled")
        if (event.error != null) add("→ ✗")
        if (event.mocked) add("[mock]")
        add("(${event.durationMs}ms)")
    }.joinToString(" ")

    fun metadata(event: NetworkLogEvent): Map<String, String> = buildMap {
        put("method", event.method)
        put("url", event.url)
        put("durationMs", event.durationMs.toString())
        put("reqBytes", event.requestBytes.toString())
        put("respBytes", event.responseBytes.toString())
        event.statusCode?.let { put("status", it.toString()) }
        event.error?.let { put("error", it) }
        if (event.cancelled) put("cancelled", "true")
        if (event.mocked) put("mocked", "true")
        // Bodies are stored raw under their own keys.
        event.requestBody?.let { put("requestBody", it) }
        event.responseBody?.let { put("responseBody", it) }
        event.responseImageBase64?.let { put("responseImageBase64", it) }
        // Headers are stored raw, one metadata key per header.
        event.requestHeaders?.forEach { (key, value) -> put("reqH.$key", value) }
        event.responseHeaders?.forEach { (key, value) -> put("respH.$key", value) }
        // Timing lives under the `t.` prefix — the viewer's "Timing" section reads these.
        event.timing?.let { timing ->
            timing.dnsMs?.let { put("t.dnsMs", it.toString()) }
            timing.connectMs?.let { put("t.connectMs", it.toString()) }
            timing.tlsMs?.let { put("t.tlsMs", it.toString()) }
            timing.ttfbMs?.let { put("t.ttfbMs", it.toString()) }
            timing.protocolName?.let { put("t.protocol", it) }
            timing.reusedConnection?.let { put("t.reused", if (it) "true" else "false") }
        }
    }
}

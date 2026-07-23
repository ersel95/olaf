package com.olaf.network

import com.olaf.LogCategory

/**
 * Olaf network capture configuration.
 */
data class OlafNetworkConfiguration(

    /** Also log request/response bodies. **On by default** — bodies are stored raw. */
    val capturesBodies: Boolean = true,

    /** Also log request/response headers. **On by default** — headers are stored raw. */
    val capturesHeaders: Boolean = true,

    /** Bodies are truncated to this many characters when logged. */
    val maxBodyLength: Int = 8000,

    /**
     * Upper limit, in bytes, for storing an image response body as a **preview**. Images up to
     * this size are attached as base64 and rendered in the detail screen; larger ones only carry
     * their size, so RAM and disk don't balloon. `0` disables image previews.
     */
    val maxImageBodyBytes: Int = 262_144, // 256 KB

    /** The category network records are logged under. */
    val category: LogCategory = LogCategory.Network,

    /**
     * **Only** requests whose URL contains one of these fragments are captured; empty means all.
     * E.g. to capture just your own API: `listOf("api-gateway", "myapp.com")`.
     */
    val includedUrls: List<String> = emptyList(),

    /**
     * Requests containing one of these URL fragments are skipped entirely.
     * E.g. to hide SDK noise: `listOf("firebaseio", "crashlytics", "googleapis")`.
     */
    val excludedUrls: List<String> = emptyList(),

    /**
     * Decoders for bodies Olaf can't read as text — Protobuf and friends. Tried in order; the
     * first non-null result wins. See [BodyDecoder], which also covers compressed bodies.
     */
    val bodyDecoders: List<BodyDecoder> = emptyList()
) {

    private val normalizedIncluded = includedUrls.map { it.lowercase() }
    private val normalizedExcluded = excludedUrls.map { it.lowercase() }

    /** Allow/deny filter — exclusion always wins over inclusion. */
    fun shouldCapture(url: String?): Boolean {
        val target = url?.lowercase() ?: return normalizedIncluded.isEmpty()
        if (normalizedExcluded.any { target.contains(it) }) return false
        if (normalizedIncluded.isNotEmpty()) return normalizedIncluded.any { target.contains(it) }
        return true
    }

    companion object {
        val Default = OlafNetworkConfiguration()
    }
}

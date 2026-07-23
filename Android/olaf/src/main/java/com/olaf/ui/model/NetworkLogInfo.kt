package com.olaf.ui.model

import com.olaf.LogCategory
import com.olaf.LogEntry
import java.util.Base64

/**
 * Parses the metadata of a `network`-category [LogEntry] into structured info. The keys are the
 * ones `NetworkLogComposer` writes — the same set the iOS package uses.
 */
internal data class NetworkLogInfo(
    val method: String?,
    val url: String?,
    val statusCode: Int?,
    val durationMs: Long?,
    val requestBytes: Long?,
    val responseBytes: Long?,
    val error: String?,
    /** Cancelled before completing — not a failure; logged at INFO. */
    val cancelled: Boolean,
    /** Produced by a mock, so no network call was made. */
    val mocked: Boolean,
    val requestBody: String?,
    val responseBody: String?,
    /** Image response body, when it was captured under the size limit. */
    val responseImageBytes: ByteArray?,
    val requestHeaders: List<Pair<String, String>>,
    val responseHeaders: List<Pair<String, String>>,
    val dnsMs: Long?,
    val connectMs: Long?,
    val tlsMs: Long?,
    val ttfbMs: Long?,
    val protocolName: String?,
    val reusedConnection: Boolean?
) {

    /** Should the detail screen show a "Timing" section? */
    val hasTimings: Boolean
        get() = dnsMs != null || connectMs != null || tlsMs != null ||
            ttfbMs != null || protocolName != null || reusedConnection != null

    /** Path (plus query) — the short form shown in a list row. */
    val path: String
        get() {
            val raw = url ?: return "-"
            val withoutScheme = raw.substringAfter("://", raw)
            val index = withoutScheme.indexOf('/')
            return if (index < 0) "/" else withoutScheme.substring(index)
        }

    val host: String
        get() {
            val raw = url ?: return ""
            return raw.substringAfter("://", raw).substringBefore('/').substringBefore('?')
        }

    /**
     * Match pattern the mock editor suggests: host + path without the query — broad enough to
     * catch every call to the endpoint, narrow enough not to spill onto other endpoints.
     */
    val suggestedMockPattern: String
        get() = host + path.substringBefore('?')

    val isFailure: Boolean
        get() = error != null || (statusCode != null && statusCode >= 400)

    override fun equals(other: Any?): Boolean = this === other ||
        (other is NetworkLogInfo && url == other.url && statusCode == other.statusCode && method == other.method)

    override fun hashCode(): Int = (url?.hashCode() ?: 0) * 31 + (statusCode ?: 0)

    companion object {
        /**
         * Returns `null` when the entry isn't a captured network record. Message-only entries the
         * host logs into the `network` category have no `url` key, and must fall back to the plain
         * message row instead of rendering as an empty network row.
         */
        fun from(entry: LogEntry): NetworkLogInfo? {
            if (entry.category != LogCategory.Network) return null
            val metadata = entry.metadata
            metadata["url"] ?: return null

            return NetworkLogInfo(
                method = metadata["method"],
                url = metadata["url"],
                statusCode = metadata["status"]?.toIntOrNull(),
                durationMs = metadata["durationMs"]?.toLongOrNull(),
                requestBytes = metadata["reqBytes"]?.toLongOrNull(),
                responseBytes = metadata["respBytes"]?.toLongOrNull(),
                error = metadata["error"],
                cancelled = metadata["cancelled"] == "true",
                mocked = metadata["mocked"] == "true",
                requestBody = metadata["requestBody"],
                responseBody = metadata["responseBody"],
                responseImageBytes = metadata["responseImageBase64"]?.let {
                    runCatching { Base64.getDecoder().decode(it) }.getOrNull()
                },
                requestHeaders = metadata.headers("reqH."),
                responseHeaders = metadata.headers("respH."),
                dnsMs = metadata["t.dnsMs"]?.toLongOrNull(),
                connectMs = metadata["t.connectMs"]?.toLongOrNull(),
                tlsMs = metadata["t.tlsMs"]?.toLongOrNull(),
                ttfbMs = metadata["t.ttfbMs"]?.toLongOrNull(),
                protocolName = metadata["t.protocol"],
                reusedConnection = metadata["t.reused"]?.let { it == "true" }
            )
        }

        private fun Map<String, String>.headers(prefix: String): List<Pair<String, String>> =
            filterKeys { it.startsWith(prefix) }
                .map { (key, value) -> key.removePrefix(prefix) to value }
                .sortedBy { it.first.lowercase() }
    }
}

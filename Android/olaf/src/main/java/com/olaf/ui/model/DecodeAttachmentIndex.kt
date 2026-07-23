package com.olaf.ui.model

import com.olaf.LogCategory
import com.olaf.LogEntry
import kotlin.math.abs

/**
 * Folds `decoding` entries into the network entry they belong to — same host+path, nearest in
 * time — so the list shows one badged network row instead of N separate decode rows.
 *
 * A decode entry with no resolvable `url`, or with no network call nearby, stays unattached and
 * keeps rendering as a normal row: nothing is ever silently dropped.
 */
internal data class DecodeAttachmentIndex(
    /** Network entry id → its decode-error entries, chronological. */
    val byNetworkId: Map<String, List<LogEntry>>,
    /** Ids of decode entries that were attached, and are therefore hidden from the flat list. */
    val attachedIds: Set<String>
) {

    fun errors(entry: LogEntry): List<LogEntry> = byNetworkId[entry.id].orEmpty()

    companion object {
        val Empty = DecodeAttachmentIndex(emptyMap(), emptySet())

        /**
         * How far apart a decode entry and its network call may be. Decoding runs right after the
         * response completes, so 30s comfortably covers thread hops while keeping repeated calls
         * to the same endpoint from cross-matching.
         */
        private const val ATTACH_WINDOW_MS = 30_000L

        fun build(entries: List<LogEntry>): DecodeAttachmentIndex {
            val networkByKey = HashMap<String, MutableList<Pair<String, Long>>>()
            for (entry in entries) {
                if (entry.category != LogCategory.Network) continue
                val key = entry.metadata["url"]?.let(::endpointKey) ?: continue
                networkByKey.getOrPut(key) { mutableListOf() }
                    .add(entry.id to entry.date.toEpochMilli())
            }
            if (networkByKey.isEmpty()) return Empty

            val byNetworkId = HashMap<String, MutableList<LogEntry>>()
            val attachedIds = HashSet<String>()

            for (entry in entries) {
                if (entry.category != LogCategory.Decoding) continue
                val key = entry.metadata["url"]?.let(::endpointKey) ?: continue
                val candidates = networkByKey[key] ?: continue
                val timestamp = entry.date.toEpochMilli()
                val nearest = candidates.minByOrNull { abs(it.second - timestamp) } ?: continue
                if (abs(nearest.second - timestamp) > ATTACH_WINDOW_MS) continue

                byNetworkId.getOrPut(nearest.first) { mutableListOf() }.add(entry)
                attachedIds.add(entry.id)
            }

            return DecodeAttachmentIndex(byNetworkId, attachedIds)
        }

        /**
         * `https://host/path?query` → `host/path`. Scheme and query are dropped: the capture side
         * logs the full URL with its query, while a decode reporter usually has only the path —
         * both have to land on the same key.
         */
        fun endpointKey(url: String): String? {
            val afterScheme = url.substringAfter("://", url)
            val host = afterScheme.substringBefore('/').substringBefore('?')
            var path = afterScheme.substringAfter('/', "").substringBefore('?')
            if (path.isNotEmpty()) path = "/$path"
            if (path.endsWith("/")) path = path.dropLast(1)
            return when {
                host.isNotEmpty() -> host + path
                path.isNotEmpty() -> path
                else -> null
            }
        }
    }
}

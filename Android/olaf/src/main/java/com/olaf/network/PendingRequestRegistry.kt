package com.olaf.network

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** An in-flight (not yet completed) network capture. */
data class PendingNetworkRequest(
    val id: String,
    val method: String,
    val url: String,
    val startedAtMillis: Long
) {
    /** Seconds elapsed since the request started. */
    val elapsedSeconds: Long
        get() = ((System.currentTimeMillis() - startedAtMillis) / 1000).coerceAtLeast(0)
}

/**
 * Registry of in-flight captures. [OlafInterceptor] registers a request when it starts and drops
 * it on completion (success, failure or cancellation). This feeds the viewer's "Active requests"
 * section, which polls a snapshot on a timer — no separate broadcast is needed.
 */
internal object PendingRequestRegistry {

    private val items = ConcurrentHashMap<String, PendingNetworkRequest>()

    fun register(method: String, url: String): String {
        val id = UUID.randomUUID().toString()
        items[id] = PendingNetworkRequest(id, method, url, System.currentTimeMillis())
        return id
    }

    fun unregister(id: String) {
        items.remove(id)
    }

    /** Snapshot ordered by start time, oldest first. */
    fun snapshot(): List<PendingNetworkRequest> = items.values.sortedBy { it.startedAtMillis }

    /** For test isolation. */
    fun removeAll() {
        items.clear()
    }
}

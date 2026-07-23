package com.olaf.ui.model

import com.olaf.LogEntry
import kotlin.math.roundToInt

/**
 * Summary statistics over the currently visible network records. A pure computation, so it is
 * directly testable; the viewer's statistics screen feeds it the filtered list.
 */
internal data class NetworkStats(
    val totalRequests: Int,
    /** 4xx/5xx or a transport failure — cancellations are counted separately. */
    val failureCount: Int,
    val cancelledCount: Int,
    val averageDurationMs: Long?,
    val medianDurationMs: Long?,
    val p95DurationMs: Long?,
    val totalRequestBytes: Long,
    val totalResponseBytes: Long,
    /** HTTP methods, most frequent first. */
    val methodCounts: List<Pair<String, Int>>,
    /** Status classes in a fixed order, with empty classes omitted. */
    val statusClassCounts: List<Pair<String, Int>>,
    /** The five busiest hosts. */
    val hostCounts: List<Pair<String, Int>>,
    /** The five slowest requests. */
    val slowest: List<Pair<String, Long>>
) {

    val failurePercent: Int
        get() = if (totalRequests > 0) {
            (failureCount.toDouble() / totalRequests * 100).roundToInt()
        } else {
            0
        }

    companion object {
        private val statusOrder = listOf("2xx", "3xx", "4xx", "5xx", "Error", "Cancelled")

        fun compute(entries: List<LogEntry>): NetworkStats {
            val infos = entries.mapNotNull(NetworkLogInfo::from)

            val methodTally = LinkedHashMap<String, Int>()
            val statusTally = LinkedHashMap<String, Int>()
            val hostTally = LinkedHashMap<String, Int>()
            val durations = mutableListOf<Long>()
            val slow = mutableListOf<Pair<String, Long>>()
            var failures = 0
            var cancelled = 0
            var requestBytes = 0L
            var responseBytes = 0L

            for (info in infos) {
                val method = (info.method ?: "GET").uppercase()
                methodTally[method] = (methodTally[method] ?: 0) + 1

                val statusClass = statusClassOf(info)
                statusTally[statusClass] = (statusTally[statusClass] ?: 0) + 1

                if (info.host.isNotEmpty()) hostTally[info.host] = (hostTally[info.host] ?: 0) + 1

                when {
                    info.cancelled -> cancelled++
                    info.isFailure -> failures++
                }

                requestBytes += info.requestBytes ?: 0
                responseBytes += info.responseBytes ?: 0

                info.durationMs?.let {
                    durations.add(it)
                    slow.add(info.path to it)
                }
            }

            durations.sort()

            return NetworkStats(
                totalRequests = infos.size,
                failureCount = failures,
                cancelledCount = cancelled,
                averageDurationMs = durations.takeIf { it.isNotEmpty() }?.let { it.sum() / it.size },
                medianDurationMs = durations.getOrNull(durations.size / 2),
                p95DurationMs = durations.getOrNull(
                    minOf(durations.size - 1, (durations.size * 0.95).toInt()).coerceAtLeast(0)
                ),
                totalRequestBytes = requestBytes,
                totalResponseBytes = responseBytes,
                methodCounts = methodTally.entries.sortedByDescending { it.value }.map { it.key to it.value },
                statusClassCounts = statusOrder.mapNotNull { name ->
                    statusTally[name]?.let { name to it }
                },
                hostCounts = hostTally.entries.sortedByDescending { it.value }.take(5).map { it.key to it.value },
                slowest = slow.sortedByDescending { it.second }.take(5)
            )
        }

        private fun statusClassOf(info: NetworkLogInfo): String = when {
            info.cancelled -> "Cancelled"
            info.statusCode == null -> "Error"
            info.statusCode in 200..299 -> "2xx"
            info.statusCode in 300..399 -> "3xx"
            info.statusCode in 400..499 -> "4xx"
            info.statusCode >= 500 -> "5xx"
            else -> "Error"
        }
    }
}

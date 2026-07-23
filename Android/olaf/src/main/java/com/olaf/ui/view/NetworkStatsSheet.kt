package com.olaf.ui.view

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.olaf.ui.model.NetworkStats
import com.olaf.ui.util.Formatting

/** Statistics over the entries currently on screen: error rate, durations and distributions. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NetworkStatsSheet(stats: NetworkStats, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Statistics", style = MaterialTheme.typography.titleMedium)

            if (stats.totalRequests == 0) {
                Text(
                    text = "No network records in the current view.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                return@Column
            }

            StatsBlock("Overview") {
                StatRow("Requests", stats.totalRequests.toString())
                StatRow("Failures", "${stats.failureCount} (${stats.failurePercent}%)")
                if (stats.cancelledCount > 0) StatRow("Cancelled", stats.cancelledCount.toString())
                StatRow("Sent", Formatting.byteCount(stats.totalRequestBytes))
                StatRow("Received", Formatting.byteCount(stats.totalResponseBytes))
            }

            StatsBlock("Duration") {
                StatRow("Average", stats.averageDurationMs?.let(Formatting::duration) ?: "-")
                StatRow("Median", stats.medianDurationMs?.let(Formatting::duration) ?: "-")
                StatRow("p95", stats.p95DurationMs?.let(Formatting::duration) ?: "-")
            }

            if (stats.statusClassCounts.isNotEmpty()) {
                StatsBlock("Status") {
                    stats.statusClassCounts.forEach { (name, count) -> StatRow(name, count.toString()) }
                }
            }

            if (stats.methodCounts.isNotEmpty()) {
                StatsBlock("Method") {
                    stats.methodCounts.forEach { (name, count) -> StatRow(name, count.toString()) }
                }
            }

            if (stats.hostCounts.isNotEmpty()) {
                StatsBlock("Busiest hosts") {
                    stats.hostCounts.forEach { (name, count) -> StatRow(name, count.toString()) }
                }
            }

            if (stats.slowest.isNotEmpty()) {
                StatsBlock("Slowest requests") {
                    stats.slowest.forEach { (path, duration) ->
                        StatRow(path, Formatting.duration(duration))
                    }
                }
            }
        }
    }
}

@Composable
private fun StatsBlock(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = title.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )
        content()
        HorizontalDivider(modifier = Modifier.padding(top = 6.dp))
    }
}

@Composable
private fun StatRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f, fill = false)
        )
        Text(text = value, style = MaterialTheme.typography.bodyMedium)
    }
}

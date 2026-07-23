package com.olaf.ui.view

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.olaf.LogEntry
import com.olaf.ui.model.NetworkLogInfo
import com.olaf.ui.util.Formatting

/**
 * A single row. Captured network entries render as a compact request row; everything else renders
 * as a level-coloured message row.
 */
@Composable
internal fun LogRow(entry: LogEntry, modifier: Modifier = Modifier) {
    val network = remember(entry.id) { NetworkLogInfo.from(entry) }
    if (network != null) {
        NetworkRow(info = network, entry = entry, modifier = modifier)
    } else {
        LogMessageRow(entry = entry, modifier = modifier)
    }
}

@Composable
private fun NetworkRow(info: NetworkLogInfo, entry: LogEntry, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        StatusPill(statusCode = info.statusCode, isFailure = info.isFailure)

        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                MethodBadge(method = info.method ?: "GET")
                Text(
                    text = info.path,
                    style = MaterialTheme.typography.bodyMedium,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (info.mocked) MockBadge()
            }

            Text(
                text = buildString {
                    if (info.host.isNotEmpty()) append(info.host).append("  ")
                    append(Formatting.time(entry.date))
                    info.durationMs?.let { append(" · ").append(Formatting.duration(it)) }
                    info.responseBytes?.takeIf { it > 0 }?.let {
                        append(" · ").append(Formatting.byteCount(it))
                    }
                },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun LogMessageRow(entry: LogEntry, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        LevelDot(level = entry.level, modifier = Modifier.padding(top = 6.dp))

        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                text = entry.message,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )

            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = entry.category.rawValue,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(50))
                        .padding(horizontal = 6.dp, vertical = 1.dp)
                )
                Text(
                    text = entry.level.name,
                    style = MaterialTheme.typography.labelSmall,
                    color = entry.level.color()
                )
                Text(
                    text = Formatting.time(entry.date),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

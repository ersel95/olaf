package com.olaf.ui.view

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.olaf.network.OlafNetwork
import com.olaf.network.PendingNetworkRequest
import kotlinx.coroutines.delay

/**
 * Shows in-flight requests with their elapsed time, so a hung call is obvious at a glance.
 * Polled on a one-second tick — the registry needs no separate broadcast channel.
 */
@Composable
internal fun PendingRequestsBar(modifier: Modifier = Modifier) {
    val pending by produceState(initialValue = emptyList<PendingNetworkRequest>()) {
        while (true) {
            value = OlafNetwork.pendingRequests
            delay(1_000)
        }
    }

    if (pending.isEmpty()) return

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(horizontal = 16.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = "${pending.size} request${if (pending.size == 1) "" else "s"} in flight",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        pending.take(3).forEach { request ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "${request.method} ${request.url}",
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = "${request.elapsedSeconds}s",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (request.elapsedSeconds >= 5) OlafColors.Orange else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

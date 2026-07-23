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
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.olaf.network.OlafMockResponse
import com.olaf.network.OlafNetwork

/** Lists the registered mocks and allows removing them, one by one or all at once. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MockListSheet(onDismiss: () -> Unit) {
    var mocks by remember { mutableStateOf(OlafNetwork.activeMocks) }

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
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("Mocks", style = MaterialTheme.typography.titleMedium)
                if (mocks.isNotEmpty()) {
                    TextButton(onClick = {
                        OlafNetwork.removeAllMocks()
                        mocks = OlafNetwork.activeMocks
                    }) { Text("Remove all") }
                }
            }

            if (mocks.isEmpty()) {
                Text(
                    text = "No mocks registered. A registered mock short-circuits matching " +
                        "requests, so no network call is made.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                return@Column
            }

            mocks.forEach { mock ->
                MockRow(
                    mock = mock,
                    onRemove = {
                        OlafNetwork.removeMock(mock.id)
                        mocks = OlafNetwork.activeMocks
                    }
                )
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun MockRow(mock: OlafMockResponse, onRemove: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (mock.transportError != null) {
                    StatusPill(statusCode = null, isFailure = true)
                } else {
                    StatusPill(statusCode = mock.statusCode, isFailure = mock.statusCode >= 400)
                }
                MethodBadge(mock.method ?: "ANY")
            }
            Text(
                text = mock.urlContains,
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace
            )
            Text(
                text = buildString {
                    mock.transportError?.let { append(it.name).append("  ") }
                    if (mock.delayMillis > 0) append("delay ${mock.delayMillis}ms  ")
                    append("${mock.body.size} B")
                },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        TextButton(onClick = onRemove) { Text("Remove") }
    }
}

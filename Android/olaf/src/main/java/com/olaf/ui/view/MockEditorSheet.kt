package com.olaf.ui.view

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import com.olaf.network.OlafMockResponse
import com.olaf.network.OlafNetwork
import com.olaf.ui.model.NetworkLogInfo
import com.olaf.ui.util.Formatting

/**
 * Turns a captured response into an **editable mock**, on the device and without touching code:
 * change the status, body or delay, or pick a transport error instead. Once saved, matching
 * requests get this response without hitting the network.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MockEditorSheet(
    info: NetworkLogInfo,
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    var urlContains by remember { mutableStateOf(info.suggestedMockPattern) }
    var limitToMethod by remember { mutableStateOf(true) }
    var isTransportError by remember { mutableStateOf(false) }
    var statusText by remember { mutableStateOf((info.statusCode ?: 200).toString()) }
    var delayText by remember { mutableStateOf("0") }
    var bodyText by remember { mutableStateOf(info.responseBody.orEmpty()) }
    var transportError by remember { mutableStateOf(OlafMockResponse.TransportError.NotConnectedToInternet) }

    val canSave = urlContains.isNotBlank() && (isTransportError || statusText.toIntOrNull() != null)

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
            Text("Convert to mock", style = MaterialTheme.typography.titleMedium)

            OutlinedTextField(
                value = urlContains,
                onValueChange = { urlContains = it },
                label = { Text("URL fragment") },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                text = "Later requests whose URL contains this fragment get the mock response " +
                    "without hitting the network.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            info.method?.let { method ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("Only ${method.uppercase()} requests")
                    Switch(checked = limitToMethod, onCheckedChange = { limitToMethod = it })
                }
            }

            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = !isTransportError,
                    onClick = { isTransportError = false },
                    shape = SegmentedButtonDefaults.itemShape(0, 2)
                ) { Text("Response") }
                SegmentedButton(
                    selected = isTransportError,
                    onClick = { isTransportError = true },
                    shape = SegmentedButtonDefaults.itemShape(1, 2)
                ) { Text("Transport error") }
            }

            if (isTransportError) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OlafMockResponse.TransportError.entries.forEach { error ->
                        FilterChip(
                            selected = transportError == error,
                            onClick = { transportError = error },
                            label = { Text(error.label()) }
                        )
                    }
                }
                Text(
                    text = "The chosen failure is thrown instead of an HTTP response — an offline " +
                        "or timeout scenario.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                OutlinedTextField(
                    value = statusText,
                    onValueChange = { statusText = it.filter(Char::isDigit).take(3) },
                    label = { Text("Status code") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                OutlinedTextField(
                    value = bodyText,
                    onValueChange = { bodyText = it },
                    label = { Text("Body") },
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 140.dp, max = 260.dp)
                )
                Text(
                    text = "The captured response headers are carried over to the mock.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            OutlinedTextField(
                value = delayText,
                onValueChange = { delayText = it.filter { char -> char.isDigit() }.take(6) },
                label = { Text("Delay (ms)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
            )
            Text(
                text = "While delayed, the request shows up in the active requests bar — which is " +
                    "how you check a slow-network path.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Button(
                    enabled = canSave,
                    onClick = {
                        OlafNetwork.addMock(
                            buildMock(
                                info = info,
                                urlContains = urlContains.trim(),
                                method = if (limitToMethod) info.method else null,
                                isTransportError = isTransportError,
                                transportError = transportError,
                                statusText = statusText,
                                bodyText = bodyText,
                                delayText = delayText
                            )
                        )
                        onSaved()
                    }
                ) { Text("Save") }
            }
        }
    }
}

private fun buildMock(
    info: NetworkLogInfo,
    urlContains: String,
    method: String?,
    isTransportError: Boolean,
    transportError: OlafMockResponse.TransportError,
    statusText: String,
    bodyText: String,
    delayText: String
): OlafMockResponse {
    val delay = delayText.toLongOrNull() ?: 0

    if (isTransportError) {
        return OlafMockResponse.failure(
            urlContains = urlContains,
            error = transportError,
            method = method,
            delayMillis = delay
        )
    }

    val headers = info.responseHeaders.toMap().ifEmpty {
        if (Formatting.looksLikeJson(bodyText)) mapOf("Content-Type" to "application/json") else emptyMap()
    }

    return OlafMockResponse(
        urlContains = urlContains,
        method = method,
        statusCode = statusText.toIntOrNull() ?: 200,
        headers = headers,
        body = bodyText.toByteArray(),
        delayMillis = delay
    )
}

private fun OlafMockResponse.TransportError.label(): String = when (this) {
    OlafMockResponse.TransportError.NotConnectedToInternet -> "No internet"
    OlafMockResponse.TransportError.Timeout -> "Timed out"
    OlafMockResponse.TransportError.HostNotFound -> "Host not found"
}

package com.olaf.ui.view

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
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
import androidx.compose.ui.unit.dp
import com.olaf.network.OlafMockEndpoint
import com.olaf.network.OlafMockPayload
import com.olaf.network.OlafMockResponse
import com.olaf.network.OlafMockTemplate
import com.olaf.network.OlafMockVariant
import com.olaf.network.OlafNetwork
import com.olaf.ui.model.NetworkLogInfo
import com.olaf.ui.util.Formatting

/** What the mock editor was opened for. */
internal sealed interface MockEditorTarget {

    /** A new variant, built from a captured entry. The endpoint is created or extended on save. */
    data class New(val info: NetworkLogInfo) : MockEditorTarget

    /** An existing variant of an existing endpoint. */
    data class Existing(val endpoint: OlafMockEndpoint, val variant: OlafMockVariant) : MockEditorTarget
}

/**
 * Turns a captured response into an **editable mock variant**, on the device and without touching
 * code: change the status, body or delay, pick a transport error, apply a saved template, or put
 * the response back to what was captured.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MockEditorSheet(
    info: NetworkLogInfo,
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        MockEditorContent(
            target = MockEditorTarget.New(info),
            onCancel = onDismiss,
            onSaved = onSaved
        )
    }
}

/** The editor body — also embedded in the mock list when an existing variant is edited. */
@Composable
internal fun MockEditorContent(
    target: MockEditorTarget,
    onCancel: () -> Unit,
    onSaved: () -> Unit
) {
    val isEditing = target is MockEditorTarget.Existing
    val sourceMethod = when (target) {
        is MockEditorTarget.New -> target.info.method
        is MockEditorTarget.Existing -> target.endpoint.method
    }
    val capturedPayload = remember(target) {
        when (target) {
            is MockEditorTarget.New -> capturedPayloadOf(target.info)
            is MockEditorTarget.Existing -> target.variant.capturedPayload
        }
    }
    val initialPayload = remember(target) {
        when (target) {
            is MockEditorTarget.New -> capturedPayload
            is MockEditorTarget.Existing -> target.variant.payload
        }
    }

    var urlContains by remember(target) {
        mutableStateOf(
            when (target) {
                is MockEditorTarget.New -> target.info.suggestedMockPattern
                is MockEditorTarget.Existing -> target.endpoint.urlContains
            }
        )
    }
    var variantName by remember(target) {
        mutableStateOf(
            when (target) {
                is MockEditorTarget.New -> defaultVariantName(target.info.statusCode)
                is MockEditorTarget.Existing -> target.variant.name
            }
        )
    }
    var limitToMethod by remember(target) { mutableStateOf(sourceMethod != null) }
    var isTransportError by remember(target) { mutableStateOf(initialPayload.transportError != null) }
    var statusText by remember(target) { mutableStateOf(initialPayload.statusCode.toString()) }
    var bodyText by remember(target) { mutableStateOf(String(initialPayload.body, Charsets.UTF_8)) }
    var delayText by remember(target) { mutableStateOf(initialPayload.delayMillis.toString()) }
    var transportError by remember(target) {
        mutableStateOf(initialPayload.transportError ?: OlafMockResponse.TransportError.NotConnectedToInternet)
    }
    var headers by remember(target) { mutableStateOf(initialPayload.headers) }
    var templates by remember { mutableStateOf(OlafNetwork.mockTemplates) }
    var templateNamePrompt by remember { mutableStateOf<String?>(null) }

    fun currentPayload(): OlafMockPayload {
        val delay = delayText.toLongOrNull() ?: 0
        if (isTransportError) {
            return OlafMockPayload.failure(transportError, delay)
        }
        val resolvedHeaders = headers.ifEmpty {
            if (Formatting.looksLikeJson(bodyText)) mapOf("Content-Type" to "application/json") else emptyMap()
        }
        return OlafMockPayload(
            statusCode = statusText.toIntOrNull() ?: 200,
            headers = resolvedHeaders,
            body = bodyText.toByteArray(),
            delayMillis = delay
        )
    }

    fun fill(payload: OlafMockPayload) {
        isTransportError = payload.transportError != null
        payload.transportError?.let { transportError = it }
        statusText = payload.statusCode.toString()
        bodyText = String(payload.body, Charsets.UTF_8)
        delayText = payload.delayMillis.toString()
        headers = payload.headers
    }

    fun save() {
        val name = variantName.trim()
        when (target) {
            is MockEditorTarget.Existing -> {
                val payload = currentPayload()
                OlafNetwork.updateVariant(target.variant.id, target.endpoint.id) { variant ->
                    variant.copy(name = name, payload = payload)
                }
            }

            is MockEditorTarget.New -> {
                val pattern = urlContains.trim()
                val method = if (limitToMethod) sourceMethod else null
                val variant = OlafMockVariant(name = name, payload = currentPayload())
                // Saving a second response for a rule that already exists extends that endpoint —
                // a duplicate entry would sit behind the first one and never be served.
                val existing = OlafNetwork.mockEndpoints.firstOrNull {
                    it.urlContains.lowercase() == pattern.lowercase() &&
                        it.method?.uppercase() == method?.uppercase()
                }
                if (existing != null) {
                    OlafNetwork.addVariant(variant, existing.id)
                } else {
                    OlafNetwork.addEndpoint(
                        OlafMockEndpoint(
                            urlContains = pattern,
                            method = method,
                            variants = listOf(variant),
                            activeVariantId = variant.id
                        )
                    )
                }
            }
        }
        onSaved()
    }

    val canSave = variantName.isNotBlank() &&
        (isEditing || urlContains.isNotBlank()) &&
        (isTransportError || statusText.toIntOrNull() != null)
    val isModified = currentPayload() != capturedPayload

    templateNamePrompt?.let { pending ->
        TemplateNameDialog(
            initialName = pending,
            onDismiss = { templateNamePrompt = null },
            onConfirm = { name ->
                OlafNetwork.addTemplate(OlafMockTemplate(name = name, payload = currentPayload()))
                templates = OlafNetwork.mockTemplates
                templateNamePrompt = null
            }
        )
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = if (isEditing) "Edit variant" else "Convert to mock",
            style = MaterialTheme.typography.titleMedium
        )

        OutlinedTextField(
            value = variantName,
            onValueChange = { variantName = it },
            label = { Text("Variant name") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Text(
            text = "The name this response is listed under on the endpoint — \"Success\", " +
                "\"Empty\", \"500\". Several can be saved and switched between.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (isEditing) {
            Text(
                text = urlContains,
                style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace)
            )
            Text(
                text = "The match rule belongs to the endpoint and is shared by all of its variants.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
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

            sourceMethod?.let { method ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("Only ${method.uppercase()} requests")
                    Switch(checked = limitToMethod, onCheckedChange = { limitToMethod = it })
                }
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

        Text("Library", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(
                enabled = isModified,
                onClick = { fill(capturedPayload) }
            ) { Text("Reset to captured") }
            TextButton(onClick = { templateNamePrompt = variantName }) { Text("Save as template") }
        }
        Text(
            text = if (isModified) {
                "Reset restores the response this variant was created from, discarding the edits above."
            } else {
                "This response matches the one it was created from — nothing to reset."
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            templates.forEach { template ->
                AssistChip(
                    onClick = {
                        fill(template.payload)
                        if (variantName.isBlank()) variantName = template.name
                    },
                    label = { Text(template.name) }
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End
        ) {
            TextButton(onClick = onCancel) { Text("Cancel") }
            Button(enabled = canSave, onClick = { save() }) { Text("Save") }
        }
    }
}

@Composable
private fun TemplateNameDialog(
    initialName: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var name by remember { mutableStateOf(initialName) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Save as template") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true
                )
                Text(
                    text = "The response is saved without a URL, so it can be reused on any " +
                        "endpoint or as the global override.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        confirmButton = {
            TextButton(enabled = name.isNotBlank(), onClick = { onConfirm(name.trim()) }) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

/** The response a captured entry starts the editor with — also what "Reset to captured" restores. */
private fun capturedPayloadOf(info: NetworkLogInfo): OlafMockPayload = OlafMockPayload(
    statusCode = info.statusCode ?: 200,
    headers = info.responseHeaders.toMap(),
    body = info.responseBody.orEmpty().toByteArray()
)

/** A first guess at the variant name, so the common case needs no typing. */
private fun defaultVariantName(statusCode: Int?): String =
    statusCode?.let { "$it response" } ?: "Captured"

private fun OlafMockResponse.TransportError.label(): String = when (this) {
    OlafMockResponse.TransportError.NotConnectedToInternet -> "No internet"
    OlafMockResponse.TransportError.Timeout -> "Timed out"
    OlafMockResponse.TransportError.HostNotFound -> "Host not found"
}

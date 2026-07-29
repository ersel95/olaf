package com.olaf.ui.view

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
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
import com.olaf.network.OlafMockEndpoint
import com.olaf.network.OlafMockPayload
import com.olaf.network.OlafMockScenario
import com.olaf.network.OlafMockTemplate
import com.olaf.network.OlafMockVariant
import com.olaf.network.OlafNetwork

/**
 * The mocking hub: which endpoints are mocked and with which variant, the global override, and
 * saved scenarios.
 *
 * New endpoints arrive via **"Convert to mock"** in a log's detail screen. From here you switch
 * variants, send an endpoint back to **Original** (real backend, definitions kept), or flip the
 * whole set at once with a scenario. Everything lives in one sheet with its own back navigation —
 * nesting bottom sheets would fight the sheet's own gesture handling.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MockListSheet(onDismiss: () -> Unit) {
    var screen by remember { mutableStateOf<MockScreen>(MockScreen.Endpoints) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        when (val current = screen) {
            MockScreen.Endpoints -> MockEndpointsScreen(
                onOpenEndpoint = { screen = MockScreen.Variants(it) },
                onOpenTemplates = { screen = MockScreen.Templates }
            )

            MockScreen.Templates -> MockTemplatesScreen(
                onBack = { screen = MockScreen.Endpoints }
            )

            is MockScreen.Variants -> MockVariantsScreen(
                endpointId = current.endpointId,
                onBack = { screen = MockScreen.Endpoints },
                onEditVariant = { endpoint, variant ->
                    screen = MockScreen.Editor(endpoint.id, variant.id)
                }
            )

            is MockScreen.Editor -> {
                val endpoint = OlafNetwork.mockEndpoints.firstOrNull { it.id == current.endpointId }
                val variant = endpoint?.variants?.firstOrNull { it.id == current.variantId }
                if (endpoint == null || variant == null) {
                    screen = MockScreen.Endpoints
                } else {
                    MockEditorContent(
                        target = MockEditorTarget.Existing(endpoint, variant),
                        onCancel = { screen = MockScreen.Variants(endpoint.id) },
                        onSaved = { screen = MockScreen.Variants(endpoint.id) }
                    )
                }
            }
        }
    }
}

/** Where the mock sheet currently is. */
private sealed interface MockScreen {
    object Endpoints : MockScreen
    object Templates : MockScreen
    data class Variants(val endpointId: String) : MockScreen
    data class Editor(val endpointId: String, val variantId: String) : MockScreen
}

// MARK: - Endpoint list

@Composable
private fun MockEndpointsScreen(
    onOpenEndpoint: (String) -> Unit,
    onOpenTemplates: () -> Unit
) {
    var endpoints by remember { mutableStateOf(OlafNetwork.mockEndpoints) }
    var templates by remember { mutableStateOf(OlafNetwork.mockTemplates) }
    var scenarios by remember { mutableStateOf(OlafNetwork.mockScenarios) }
    var globalTemplateId by remember { mutableStateOf(OlafNetwork.globalMockTemplateId) }
    var isNamingScenario by remember { mutableStateOf(false) }

    fun reload() {
        endpoints = OlafNetwork.mockEndpoints
        templates = OlafNetwork.mockTemplates
        scenarios = OlafNetwork.mockScenarios
        globalTemplateId = OlafNetwork.globalMockTemplateId
    }

    if (isNamingScenario) {
        ScenarioNameDialog(
            onDismiss = { isNamingScenario = false },
            onConfirm = { name ->
                OlafNetwork.saveScenario(name)
                isNamingScenario = false
                reload()
            }
        )
    }

    MockSheetColumn {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Mocks", style = MaterialTheme.typography.titleMedium)
            Row {
                TextButton(
                    enabled = globalTemplateId != null || endpoints.any { it.activeVariantId != null },
                    onClick = {
                        OlafNetwork.resetAllToOriginal()
                        reload()
                    }
                ) { Text("Reset all") }
                TextButton(
                    enabled = endpoints.isNotEmpty() || globalTemplateId != null,
                    onClick = {
                        OlafNetwork.removeAllMocks()
                        reload()
                    }
                ) { Text("Remove all") }
            }
        }

        // Global override
        Text("Global override", style = MaterialTheme.typography.titleSmall)
        Text(
            text = "Served to every captured request that has no endpoint of its own. Unlike " +
                "endpoint mocks it respects the capture filters, and endpoints set to Original " +
                "are left alone.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = globalTemplateId == null,
                onClick = {
                    OlafNetwork.globalMockTemplateId = null
                    reload()
                },
                label = { Text("None") }
            )
            templates.forEach { template ->
                FilterChip(
                    selected = globalTemplateId == template.id,
                    onClick = {
                        OlafNetwork.globalMockTemplateId = template.id
                        reload()
                    },
                    label = { Text(template.name) }
                )
            }
        }
        TextButton(onClick = onOpenTemplates) { Text("Manage templates") }

        HorizontalDivider()

        // Endpoints
        Text("Endpoints", style = MaterialTheme.typography.titleSmall)
        if (endpoints.isEmpty()) {
            Text(
                text = "No mocked endpoints. Add one from a log's detail screen via \"Convert to " +
                    "mock\"; matching requests then get that response without hitting the network.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            endpoints.forEach { endpoint ->
                EndpointRow(
                    endpoint = endpoint,
                    onOpen = { onOpenEndpoint(endpoint.id) },
                    onReset = {
                        OlafNetwork.resetEndpoint(endpoint.id)
                        reload()
                    },
                    onRemove = {
                        OlafNetwork.removeEndpoint(endpoint.id)
                        reload()
                    }
                )
                HorizontalDivider()
            }
            Text(
                text = "If several endpoints match, the first one added wins. Mocks reset on app restart.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        HorizontalDivider()

        // Scenarios
        Text("Scenarios", style = MaterialTheme.typography.titleSmall)
        Text(
            text = "Applying a scenario switches every endpoint at once; endpoints it doesn't name " +
                "go back to Original.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        scenarios.forEach { scenario ->
            ScenarioRow(
                scenario = scenario,
                templates = templates,
                onApply = {
                    OlafNetwork.applyScenario(scenario.id)
                    reload()
                },
                onRemove = {
                    OlafNetwork.removeScenario(scenario.id)
                    reload()
                }
            )
        }
        TextButton(
            enabled = endpoints.isNotEmpty() || globalTemplateId != null,
            onClick = { isNamingScenario = true }
        ) { Text("Save current state…") }
    }
}

@Composable
private fun EndpointRow(
    endpoint: OlafMockEndpoint,
    onOpen: () -> Unit,
    onReset: () -> Unit,
    onRemove: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .clickable(onClick = onOpen)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                val variant = endpoint.activeVariant
                if (variant == null) {
                    StatusPill(statusCode = null, isFailure = false)
                } else if (variant.payload.transportError != null) {
                    StatusPill(statusCode = null, isFailure = true)
                } else {
                    StatusPill(
                        statusCode = variant.payload.statusCode,
                        isFailure = variant.payload.statusCode >= 400
                    )
                }
                MethodBadge(endpoint.method ?: "ANY")
            }
            Text(
                text = endpoint.urlContains,
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace
            )
            Text(
                text = endpoint.activeVariant?.let { "${it.name}  ${payloadSummary(it.payload)}" }
                    ?: "Original  ${endpoint.variants.size} variant(s) saved",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        TextButton(
            enabled = endpoint.activeVariantId != null,
            onClick = onReset
        ) { Text("Reset") }
        TextButton(onClick = onRemove) { Text("Remove") }
    }
}

@Composable
private fun ScenarioRow(
    scenario: OlafMockScenario,
    templates: List<OlafMockTemplate>,
    onApply: () -> Unit,
    onRemove: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .clickable(onClick = onApply)
        ) {
            Text(scenario.name, style = MaterialTheme.typography.bodyMedium)
            val globalName = scenario.globalTemplateId
                ?.let { id -> templates.firstOrNull { it.id == id }?.name }
            Text(
                text = buildString {
                    append("${scenario.selections.size} endpoint(s)")
                    if (globalName != null) append("  global: $globalName")
                },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        TextButton(onClick = onApply) { Text("Apply") }
        TextButton(onClick = onRemove) { Text("Remove") }
    }
}

// MARK: - Variants

@Composable
private fun MockVariantsScreen(
    endpointId: String,
    onBack: () -> Unit,
    onEditVariant: (OlafMockEndpoint, OlafMockVariant) -> Unit
) {
    var endpoint by remember { mutableStateOf(OlafNetwork.mockEndpoints.firstOrNull { it.id == endpointId }) }
    val templates = remember { OlafNetwork.mockTemplates }

    fun reload() {
        endpoint = OlafNetwork.mockEndpoints.firstOrNull { it.id == endpointId }
    }

    MockSheetColumn {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Variants", style = MaterialTheme.typography.titleMedium)
            TextButton(onClick = onBack) { Text("Back") }
        }

        val current = endpoint
        if (current == null) {
            Text(
                text = "This endpoint was removed.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            return@MockSheetColumn
        }

        Text(
            text = current.urlContains,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace
        )

        // Original
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable {
                    OlafNetwork.resetEndpoint(endpointId)
                    reload()
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("Original", style = MaterialTheme.typography.bodyMedium)
                Text(
                    text = "Real backend — the global override doesn't apply either",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (current.activeVariantId == null) {
                Text("Serving", style = MaterialTheme.typography.labelSmall)
            }
        }
        HorizontalDivider()

        current.variants.forEach { variant ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clickable {
                            OlafNetwork.selectVariant(variant.id, endpointId)
                            reload()
                        }
                ) {
                    Text(variant.name, style = MaterialTheme.typography.bodyMedium)
                    Text(
                        text = payloadSummary(variant.payload) +
                            if (variant.id == current.activeVariantId) "  · serving" else "",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                TextButton(onClick = { onEditVariant(current, variant) }) { Text("Edit") }
                TextButton(onClick = {
                    OlafNetwork.removeVariant(variant.id, endpointId)
                    reload()
                }) { Text("Remove") }
            }
            HorizontalDivider()
        }

        Text(
            text = "Tap a variant to serve it. Removing the served one falls back to Original.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Text("Add from template", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            templates.forEach { template ->
                AssistChip(
                    onClick = {
                        OlafNetwork.addVariant(
                            OlafMockVariant(name = template.name, payload = template.payload),
                            endpointId
                        )
                        reload()
                    },
                    label = { Text(template.name) }
                )
            }
        }
    }
}

// MARK: - Templates

@Composable
private fun MockTemplatesScreen(onBack: () -> Unit) {
    var templates by remember { mutableStateOf(OlafNetwork.mockTemplates) }

    MockSheetColumn {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Templates", style = MaterialTheme.typography.titleMedium)
            TextButton(onClick = onBack) { Text("Back") }
        }
        Text(
            text = "URL-agnostic responses: apply one to an endpoint as a variant, or switch it on " +
                "as the global override. Built-in templates can't be deleted.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        templates.forEach { template ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = if (template.isBuiltIn) "${template.name}  (built-in)" else template.name,
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = payloadSummary(template.payload),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (!template.isBuiltIn) {
                    TextButton(onClick = {
                        OlafNetwork.removeTemplate(template.id)
                        templates = OlafNetwork.mockTemplates
                    }) { Text("Remove") }
                }
            }
            HorizontalDivider()
        }
    }
}

// MARK: - Shared bits

@Composable
private fun MockSheetColumn(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        content()
    }
}

@Composable
private fun ScenarioNameDialog(onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var name by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Save scenario") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true
                )
                Text(
                    text = "Stores which variant each endpoint is on, plus the global override, so " +
                        "you can come back to this exact setup.",
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

/** One-line description of a mock response — shared by the variant, template and endpoint rows. */
internal fun payloadSummary(payload: OlafMockPayload): String = buildString {
    val transportError = payload.transportError
    if (transportError != null) {
        append(transportError.name)
    } else {
        append("→ ${payload.statusCode}")
        if (payload.body.isNotEmpty()) append("  ${payload.body.size} B")
    }
    if (payload.delayMillis > 0) append("  ${payload.delayMillis}ms delay")
}

package com.olaf.ui.view

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.text.style.TextOverflow
import kotlinx.coroutines.launch
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.heightIn
import com.olaf.LogEntry
import com.olaf.ui.model.NetworkLogInfo
import com.olaf.ui.util.CurlBuilder
import com.olaf.ui.util.Formatting
import com.olaf.ui.util.copyToClipboard

/**
 * Detail view of a single entry. Network records get a structured breakdown (summary, timing,
 * request, response); everything else shows the message plus its raw metadata.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LogDetailScreen(
    entry: LogEntry,
    decodeErrors: List<LogEntry> = emptyList(),
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val network = remember(entry.id) { NetworkLogInfo.from(entry) }
    val snackbarHostState = remember { SnackbarHostState() }
    val coroutineScope = rememberCoroutineScope()

    var fullScreenText by remember { mutableStateOf<Pair<String, String>?>(null) }
    var isMockEditorOpen by remember { mutableStateOf(false) }

    // Copy confirmation: the platform only shows one of its own on Android 13+, so the viewer
    // provides it everywhere the library runs.
    fun copy(label: String, text: String) {
        copyToClipboard(context, label, text)
        coroutineScope.launch { snackbarHostState.showSnackbar("$label copied") }
    }

    fullScreenText?.let { (title, text) ->
        TextViewerScreen(title = title, rawText = text, onBack = { fullScreenText = null })
        return
    }

    if (isMockEditorOpen && network != null) {
        MockEditorSheet(
            info = network,
            onDismiss = { isMockEditorOpen = false },
            onSaved = { isMockEditorOpen = false }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (network != null) "Request" else "Log entry") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(OlafIcons.Back, contentDescription = "Back")
                    }
                },
                actions = {
                    if (network != null) {
                        TextButton(onClick = { isMockEditorOpen = true }) { Text("Mock") }
                    }
                    IconButton(onClick = { copy("Entry", entry.toShareText()) }) {
                        Icon(OlafIcons.Share, contentDescription = "Copy")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
        ) {
            item {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    if (network != null) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            StatusPill(network.statusCode, network.isFailure)
                            MethodBadge(network.method ?: "GET")
                            if (network.mocked) MockBadge()
                        }
                        SelectableValue(network.url ?: "-")
                    } else {
                        Text(text = entry.message, style = MaterialTheme.typography.bodyLarge)
                    }
                    Text(
                        text = "${entry.level.name} · ${entry.category.rawValue} · " +
                            Formatting.dateTime(entry.date),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (entry.file.isNotEmpty()) {
                        Text(
                            text = "${entry.fileName}:${entry.line} · ${entry.function} · ${entry.thread}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                HorizontalDivider()
            }

            if (decodeErrors.isNotEmpty()) {
                decodeErrorSection(decodeErrors)
            }

            if (network != null) {
                networkSections(network) { title, text -> fullScreenText = title to text }
                item {
                    Section(title = "cURL", initiallyExpanded = false) {
                        val command = remember(network) { CurlBuilder.curl(network) }
                        CodeBlock(command) { fullScreenText = "cURL" to command }
                        TextButton(onClick = { copy("cURL", command) }) { Text("Copy cURL") }
                    }
                }
            } else {
                metadataSection(entry)
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.networkSections(
    info: NetworkLogInfo,
    onOpenText: (title: String, text: String) -> Unit
) {
    info.error?.let { error ->
        item { Section(title = "Error") { SelectableValue(error) } }
    }

    item {
        Section(title = "Summary", initiallyExpanded = false) {
            KeyValue("Duration", info.durationMs?.let(Formatting::duration) ?: "-")
            KeyValue("Request size", info.requestBytes?.let(Formatting::byteCount) ?: "-")
            KeyValue("Response size", info.responseBytes?.let(Formatting::byteCount) ?: "-")
            if (info.cancelled) KeyValue("Cancelled", "yes")
        }
    }

    if (info.hasTimings) {
        item {
            Section(title = "Timing") {
                info.dnsMs?.let { KeyValue("DNS", Formatting.duration(it)) }
                info.connectMs?.let { KeyValue("TCP connect", Formatting.duration(it)) }
                info.tlsMs?.let { KeyValue("TLS", Formatting.duration(it)) }
                info.ttfbMs?.let { KeyValue("Time to first byte", Formatting.duration(it)) }
                info.protocolName?.let { KeyValue("Protocol", it) }
                info.reusedConnection?.let { KeyValue("Connection reused", if (it) "yes" else "no") }
            }
        }
    }

    if (info.requestHeaders.isNotEmpty()) {
        item {
            Section(title = "Request headers (${info.requestHeaders.size})") {
                info.requestHeaders.forEach { HeaderRow(it.first, it.second) }
            }
        }
    }

    info.requestBody?.let { body ->
        item {
            Section(title = "Request body") {
                CodeBlock(body) { onOpenText("Request body", body) }
            }
        }
    }

    if (info.responseHeaders.isNotEmpty()) {
        item {
            Section(title = "Response headers (${info.responseHeaders.size})") {
                info.responseHeaders.forEach { HeaderRow(it.first, it.second) }
            }
        }
    }

    info.responseImageBytes?.let { bytes ->
        item { Section(title = "Response image") { ImagePreview(bytes) } }
    }

    info.responseBody?.let { body ->
        item {
            Section(title = "Response body") {
                CodeBlock(body) { onOpenText("Response body", body) }
            }
        }
    }
}

/**
 * Decode failures that belong to this request. They are folded in here rather than listed as
 * their own rows, so a schema mismatch is read next to the body that caused it.
 */
private fun androidx.compose.foundation.lazy.LazyListScope.decodeErrorSection(errors: List<LogEntry>) {
    item {
        Section(title = "Decoding errors (${errors.size})") {
            errors.forEach { error ->
                error.metadata["decoding.path"]?.let { KeyValue("Field", it) }
                error.metadata["decoding.type"]?.let { KeyValue("Type", it) }
                error.metadata["decoding.detail"]?.let { KeyValue("Detail", it) }
            }
        }
    }
}

@Composable
private fun ImagePreview(bytes: ByteArray) {
    val bitmap = remember(bytes) {
        runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
    }
    if (bitmap == null) {
        Text(
            text = "Preview unavailable (${bytes.size} bytes)",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        return
    }
    Image(
        bitmap = bitmap.asImageBitmap(),
        contentDescription = "Response image",
        contentScale = ContentScale.Fit,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 260.dp)
    )
}

private fun androidx.compose.foundation.lazy.LazyListScope.metadataSection(entry: LogEntry) {
    item {
        Section(title = "Metadata") {
            if (entry.metadata.isEmpty()) {
                // Saying so beats an empty screen that reads as a rendering bug.
                Text(
                    text = "This entry carries no metadata. Pass a map to the log call to attach " +
                        "structured context.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                entry.metadata.entries.sortedBy { it.key }.forEach { KeyValue(it.key, it.value) }
            }
        }
    }
}

/**
 * A collapsible titled block. Tapping the header folds it away, which is what keeps a response
 * with fifty headers navigable.
 */
@Composable
private fun Section(
    title: String,
    initiallyExpanded: Boolean = true,
    content: @Composable () -> Unit
) {
    var expanded by remember(title) { mutableStateOf(initiallyExpanded) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = (if (expanded) "▾  " else "▸  ") + title.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
        )
        if (expanded) content()
    }
    HorizontalDivider()
}

/**
 * One header, collapsed to a single-line preview. A `set-cookie` or a bearer token can run for
 * hundreds of characters, and expanding them all at once buries the rest of the response.
 */
@Composable
private fun HeaderRow(name: String, value: String) {
    var expanded by remember(name, value) { mutableStateOf(false) }
    val isLong = value.length > HEADER_PREVIEW_LIMIT

    Column(
        verticalArrangement = Arrangement.spacedBy(1.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = isLong) { expanded = !expanded }
    ) {
        Text(
            text = name,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (expanded || !isLong) {
            SelectableValue(value)
        } else {
            Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

private const val HEADER_PREVIEW_LIMIT = 60

@Composable
private fun KeyValue(key: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(
            text = key,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        SelectableValue(value)
    }
}

@Composable
private fun SelectableValue(value: String) {
    androidx.compose.foundation.text.selection.SelectionContainer {
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace
        )
    }
}

/**
 * Bodies are already pretty-printed at capture time, so the inline block only previews them,
 * syntax-highlighted when the content is JSON. Tapping opens the full-screen viewer, which is
 * where search and line-wrap control live.
 */
@Composable
private fun CodeBlock(text: String, onOpen: () -> Unit) {
    val isJson = remember(text) { Formatting.looksLikeJson(text) }
    val rendered = remember(text, isJson) {
        val preview = if (text.length > PREVIEW_LIMIT) text.take(PREVIEW_LIMIT) + "\n…" else text
        if (isJson) JsonHighlighter.highlight(preview) else AnnotatedString(preview)
    }

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SelectionContainer {
            Text(
                text = rendered,
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(8.dp))
                    .padding(10.dp)
                    .horizontalScroll(rememberScrollState())
            )
        }
        TextButton(onClick = onOpen) { Text("Open in viewer (search, wrap, copy)") }
    }
}

private const val PREVIEW_LIMIT = 2000

/** A copyable, single-block representation of the entry. */
private fun LogEntry.toShareText(): String = buildString {
    appendLine("${Formatting.dateTime(date)} [${level.name}] [${category.rawValue}] $message")
    if (file.isNotEmpty()) appendLine("$fileName:$line · $function · $thread")
    metadata.entries.sortedBy { it.key }.forEach { appendLine("${it.key}: ${it.value}") }
}

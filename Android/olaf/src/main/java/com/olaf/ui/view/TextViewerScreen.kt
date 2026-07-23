package com.olaf.ui.view

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.olaf.ui.util.Formatting
import com.olaf.ui.util.copyToClipboard

/**
 * Full-screen, selectable and searchable text viewer for a body or a cURL command.
 *
 * Searching filters to matching lines — but when the content is JSON, a match that opens an
 * object or array pulls in the whole block, because a lone `"accounts": [` line is meaningless.
 * Disjoint results are separated with `⋯`, and highlighting survives the filtering.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun TextViewerScreen(title: String, rawText: String, onBack: () -> Unit) {
    val context = LocalContext.current
    var query by remember { mutableStateOf("") }
    var wrapLines by remember { mutableStateOf(true) }

    BackHandler(onBack = onBack)

    val isJson = remember(rawText) { Formatting.looksLikeJson(rawText) }

    val displayed = remember(rawText, query, isJson) {
        val trimmedQuery = query.trim()
        when {
            trimmedQuery.isEmpty() -> rawText
            isJson -> Formatting.searchKeepingJsonBlocks(rawText, trimmedQuery) ?: NO_MATCHES
            else -> rawText.split("\n")
                .filter { it.contains(trimmedQuery, ignoreCase = true) }
                .takeIf { it.isNotEmpty() }
                ?.joinToString("\n")
                ?: NO_MATCHES
        }
    }

    val annotated: AnnotatedString = remember(displayed, isJson) {
        if (isJson) JsonHighlighter.highlight(displayed) else AnnotatedString(displayed)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(OlafIcons.Back, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(onClick = { wrapLines = !wrapLines }) {
                        Text(if (wrapLines) "No wrap" else "Wrap")
                    }
                    IconButton(onClick = { copyToClipboard(context, title, rawText) }) {
                        Icon(OlafIcons.Share, contentDescription = "Copy")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("Search") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp)
            )

            val scrollModifier = if (wrapLines) {
                Modifier.verticalScroll(rememberScrollState())
            } else {
                Modifier
                    .verticalScroll(rememberScrollState())
                    .horizontalScroll(rememberScrollState())
            }

            SelectionContainer(modifier = Modifier.fillMaxSize()) {
                Text(
                    text = annotated,
                    fontFamily = FontFamily.Monospace,
                    softWrap = wrapLines,
                    modifier = scrollModifier.padding(16.dp)
                )
            }
        }
    }
}

private const val NO_MATCHES = "(no matches)"

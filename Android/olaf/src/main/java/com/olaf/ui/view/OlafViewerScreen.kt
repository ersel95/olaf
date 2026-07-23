package com.olaf.ui.view

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.layout.size
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.olaf.LogEntry
import com.olaf.Olaf
import com.olaf.R
import com.olaf.ui.bridge.ExternalToolRegistry
import com.olaf.ui.model.LogViewerModel
import com.olaf.ui.presentation.OlafPresenter
import com.olaf.ui.util.Formatting
import com.olaf.ui.util.shareFile
import kotlinx.coroutines.launch

/**
 * Root screen of the in-app viewer: scope switch, category chips, search, the log list and the
 * detail screen it pushes to.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OlafViewerScreen(
    onClose: () -> Unit,
    model: LogViewerModel = viewModel()
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    val scope by model.scope.collectAsStateWithLifecycle()
    val entries by model.filteredEntries.collectAsStateWithLifecycle()
    val pinned by model.pinnedEntries.collectAsStateWithLifecycle()
    val pinnedIds by model.pinnedIds.collectAsStateWithLifecycle()
    val categories by model.availableCategories.collectAsStateWithLifecycle()
    val selectedCategories by model.selectedCategories.collectAsStateWithLifecycle()
    val selectedLevels by model.enabledLevels.collectAsStateWithLifecycle()
    val selectedContentKinds by model.selectedContentKinds.collectAsStateWithLifecycle()
    val searchText by model.searchText.collectAsStateWithLifecycle()
    val isLoading by model.isLoading.collectAsStateWithLifecycle()
    val isLoadingMore by model.isLoadingMore.collectAsStateWithLifecycle()
    val hasMoreHistory by model.hasMoreHistory.collectAsStateWithLifecycle()
    val isFollowing by model.isFollowing.collectAsStateWithLifecycle()
    val isFiltering by model.isFiltering.collectAsStateWithLifecycle()
    val sessions by model.sessionGroups.collectAsStateWithLifecycle()

    val decodeIndex by model.decodeIndex.collectAsStateWithLifecycle()

    var selectedEntry by remember { mutableStateOf<LogEntry?>(null) }
    var isFilterSheetOpen by remember { mutableStateOf(false) }
    var isMenuOpen by remember { mutableStateOf(false) }
    var isStatsSheetOpen by remember { mutableStateOf(false) }
    var isMockSheetOpen by remember { mutableStateOf(false) }
    var isSelecting by remember { mutableStateOf(false) }
    var selectedIds by remember { mutableStateOf(emptySet<String>()) }

    LaunchedEffect(Unit) { model.start() }

    // Detail is a plain state switch rather than a nav graph, so the library needs no navigation
    // dependency; back returns to the list, and only then closes the viewer.
    BackHandler(enabled = selectedEntry != null) { selectedEntry = null }

    val entry = selectedEntry
    if (entry != null) {
        LogDetailScreen(
            entry = entry,
            decodeErrors = decodeIndex.errors(entry),
            onBack = { selectedEntry = null }
        )
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { OlafTitle() },
                navigationIcon = {
                    if (isSelecting) {
                        TextButton(onClick = {
                            isSelecting = false
                            selectedIds = emptySet()
                        }) { Text("Done") }
                    } else {
                        TextButton(onClick = onClose) { Text("Close") }
                    }
                },
                actions = {
                    IconButton(onClick = { isFilterSheetOpen = true }) {
                        Icon(
                            imageVector = OlafIcons.Filter,
                            contentDescription = "Filters",
                            tint = if (isFiltering) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            }
                        )
                    }
                    Box {
                        IconButton(onClick = { isMenuOpen = true }) {
                            Icon(OlafIcons.More, contentDescription = "More")
                        }
                        DropdownMenu(expanded = isMenuOpen, onDismissRequest = { isMenuOpen = false }) {
                            DropdownMenuItem(
                                text = { Text(if (isFollowing) "Pause" else "Resume") },
                                onClick = {
                                    isMenuOpen = false
                                    if (isFollowing) model.pauseFollowing() else model.resumeFollowing()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Share .log") },
                                onClick = {
                                    isMenuOpen = false
                                    coroutineScope.launch {
                                        model.exportLogFile()?.let { shareFile(context, it) }
                                    }
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Share NDJSON (raw)") },
                                onClick = {
                                    isMenuOpen = false
                                    coroutineScope.launch {
                                        model.exportNdjsonFile()?.let { shareFile(context, it) }
                                    }
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Share HAR (network)") },
                                onClick = {
                                    isMenuOpen = false
                                    coroutineScope.launch {
                                        model.exportHarFile(context.cacheDir)?.let {
                                            shareFile(context, it, mimeType = "application/json")
                                        }
                                    }
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Share Postman Collection") },
                                onClick = {
                                    isMenuOpen = false
                                    coroutineScope.launch {
                                        model.exportPostmanFile(context.cacheDir)?.let {
                                            shareFile(context, it, mimeType = "application/json")
                                        }
                                    }
                                }
                            )
                            HorizontalDivider()
                            DropdownMenuItem(
                                text = { Text("Statistics") },
                                onClick = {
                                    isMenuOpen = false
                                    isStatsSheetOpen = true
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Mocks") },
                                onClick = {
                                    isMenuOpen = false
                                    isMockSheetOpen = true
                                }
                            )
                            if (scope == LogViewerModel.Scope.SESSION) {
                                DropdownMenuItem(
                                    text = { Text("Select") },
                                    onClick = {
                                        isMenuOpen = false
                                        isSelecting = true
                                    }
                                )
                            }
                            HorizontalDivider()
                            DropdownMenuItem(
                                text = { Text("Import Logcat (1 hour)") },
                                onClick = {
                                    isMenuOpen = false
                                    coroutineScope.launch {
                                        Olaf.importLogcatEntries()
                                        model.reload()
                                    }
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Clear") },
                                onClick = {
                                    isMenuOpen = false
                                    model.clear()
                                }
                            )
                        }
                    }
                }
            )
        },
        bottomBar = {
            if (isSelecting) {
                SelectionBar(
                    count = selectedIds.size,
                    onShare = {
                        coroutineScope.launch {
                            model.exportSelected(selectedIds)?.let { shareFile(context, it) }
                        }
                    }
                )
            } else {
                ExternalToolBar()
            }
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding).fillMaxSize()) {
            ScopeSwitch(scope = scope, onSelect = model::setScope)

            OutlinedTextField(
                value = searchText,
                onValueChange = model::setSearchText,
                // Kept short so it never wraps to a second line and grows the field.
                placeholder = { Text("Search logs") },
                singleLine = true,
                shape = MaterialTheme.shapes.extraLarge,
                leadingIcon = { Icon(OlafIcons.Search, contentDescription = null) },
                trailingIcon = {
                    // Only offered once there is something to clear, so the field stays quiet.
                    if (searchText.isNotEmpty()) {
                        IconButton(onClick = { model.setSearchText("") }) {
                            Icon(OlafIcons.Clear, contentDescription = "Clear search")
                        }
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp)
            )

            CategoryFilterBar(
                categories = categories,
                selected = selectedCategories,
                onToggle = model::toggleCategory
            )

            if (scope == LogViewerModel.Scope.SESSION) {
                PendingRequestsBar()
            }

            HorizontalDivider()

            when {
                isLoading -> CenteredMessage("Loading history…", showSpinner = true)

                scope == LogViewerModel.Scope.HISTORY -> HistoryList(
                    sessions = sessions,
                    hasMore = hasMoreHistory,
                    isLoadingMore = isLoadingMore,
                    onLoadMore = model::loadOlderHistory,
                    onSelect = { selectedEntry = it }
                )

                entries.isEmpty() && pinned.isEmpty() -> EmptyState(
                    title = if (searchText.isNotEmpty() || isFiltering) "Nothing matches" else "No logs yet",
                    detail = when {
                        searchText.isNotEmpty() || isFiltering ->
                            "Try clearing the search or the filters."

                        else ->
                            "Logs and captured requests will appear here as the app runs."
                    },
                    actionLabel = if (searchText.isNotEmpty() || isFiltering) "Reset filters" else null,
                    onAction = {
                        model.setSearchText("")
                        model.resetFilters()
                    }
                )

                else -> SessionList(
                    entries = entries,
                    pinned = pinned,
                    pinnedIds = pinnedIds,
                    isSelecting = isSelecting,
                    selectedIds = selectedIds,
                    decodeErrorCount = { decodeIndex.errors(it).size },
                    onSelect = { entry ->
                        if (isSelecting) {
                            selectedIds = if (entry.id in selectedIds) {
                                selectedIds - entry.id
                            } else {
                                selectedIds + entry.id
                            }
                        } else {
                            selectedEntry = entry
                        }
                    },
                    onTogglePin = model::togglePin
                )
            }
        }
    }

    if (isStatsSheetOpen) {
        NetworkStatsSheet(stats = model.statistics(), onDismiss = { isStatsSheetOpen = false })
    }

    if (isMockSheetOpen) {
        MockListSheet(onDismiss = { isMockSheetOpen = false })
    }

    if (isFilterSheetOpen) {
        LogFilterSheet(
            levels = selectedLevels,
            categories = categories,
            selectedCategories = selectedCategories,
            contentKinds = selectedContentKinds,
            onToggleLevel = model::toggleLevel,
            onToggleCategory = model::toggleCategory,
            onToggleContentKind = model::toggleContentKind,
            onReset = model::resetFilters,
            onDismiss = { isFilterSheetOpen = false }
        )
    }
}

/**
 * The title. When the host registered a handler through `OlafUI.onLogoTap`, it becomes a button
 * that closes the viewer and hands off to the other tool.
 */
@Composable
private fun OlafTitle() {
    val handler = OlafPresenter.logoTapHandler
    val modifier = if (handler != null) {
        Modifier.clickable {
            OlafPresenter.dismiss()
            handler.invoke()
        }
    } else {
        Modifier
    }
    Image(
        painter = painterResource(R.drawable.olaf_logo),
        contentDescription = if (handler != null) "Olaf — switch tool" else "Olaf",
        contentScale = ContentScale.Fit,
        modifier = modifier.height(28.dp)
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScopeSwitch(scope: LogViewerModel.Scope, onSelect: (LogViewerModel.Scope) -> Unit) {
    val options = LogViewerModel.Scope.entries
    SingleChoiceSegmentedButtonRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp)
    ) {
        options.forEachIndexed { index, option ->
            SegmentedButton(
                selected = option == scope,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size)
            ) {
                Text(if (option == LogViewerModel.Scope.SESSION) "Session" else "History")
            }
        }
    }
}

@Composable
private fun SessionList(
    entries: List<LogEntry>,
    pinned: List<LogEntry>,
    pinnedIds: Set<String>,
    isSelecting: Boolean,
    selectedIds: Set<String>,
    decodeErrorCount: (LogEntry) -> Int,
    onSelect: (LogEntry) -> Unit,
    onTogglePin: (LogEntry) -> Unit
) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        if (pinned.isNotEmpty() && !isSelecting) {
            item(key = "pinned-header") { SectionHeader("Pinned") }
            items(pinned, key = { "pinned-${it.id}" }) { entry ->
                EntryRow(entry, pinnedIds, isSelecting, selectedIds, decodeErrorCount(entry), onSelect, onTogglePin)
            }
            item(key = "pinned-divider") { HorizontalDivider() }
        }

        items(entries, key = { it.id }) { entry ->
            EntryRow(entry, pinnedIds, isSelecting, selectedIds, decodeErrorCount(entry), onSelect, onTogglePin)
            HorizontalDivider()
        }
    }
}

@Composable
private fun EntryRow(
    entry: LogEntry,
    pinnedIds: Set<String>,
    isSelecting: Boolean,
    selectedIds: Set<String>,
    decodeErrorCount: Int,
    onSelect: (LogEntry) -> Unit,
    onTogglePin: (LogEntry) -> Unit
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (isSelecting) {
            Checkbox(
                checked = entry.id in selectedIds,
                onCheckedChange = { onSelect(entry) }
            )
        }
        LogRow(
            entry = entry,
            decodeErrorCount = decodeErrorCount,
            modifier = Modifier
                .weight(1f)
                .clickable { onSelect(entry) }
        )
        if (!isSelecting) {
            val isPinned = entry.id in pinnedIds
            val haptics = LocalHapticFeedback.current
            IconButton(onClick = {
                // Pinning has no other confirmation, so it gets the tactile one Android users expect.
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                onTogglePin(entry)
            }) {
                Icon(
                    imageVector = OlafIcons.Pin,
                    contentDescription = if (isPinned) "Unpin" else "Pin",
                    // Unpinned rows keep the affordance visible but muted, so pins stand out.
                    tint = if (isPinned) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                    }
                )
            }
        }
    }
}

/** Bottom bar of multi-select mode: how many are picked, and the share action. */
@Composable
private fun SelectionBar(count: Int, onShare: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = "$count selected",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Button(enabled = count > 0, onClick = onShare) { Text("Share") }
    }
}

@Composable
private fun HistoryList(
    sessions: List<LogViewerModel.LogSession>,
    hasMore: Boolean,
    isLoadingMore: Boolean,
    onLoadMore: () -> Unit,
    onSelect: (LogEntry) -> Unit
) {
    if (sessions.isEmpty() && !hasMore) {
        CenteredMessage("No logs found from previous sessions.", showSpinner = false)
        return
    }

    LazyColumn(modifier = Modifier.fillMaxSize()) {
        sessions.forEach { session ->
            item(key = "session-${session.id}") {
                SectionHeader("${Formatting.dateTime(session.startedAt)}  ·  ${session.entries.size} entries")
            }
            items(session.entries, key = { it.id }) { entry ->
                LogRow(entry = entry, modifier = Modifier.clickable { onSelect(entry) })
                HorizontalDivider()
            }
        }

        if (hasMore) {
            item(key = "load-more") {
                // Appearing at the end of the list triggers the next page (infinite scroll); the
                // button is the manual fallback when the automatic trigger is missed.
                LaunchedEffect(Unit) { onLoadMore() }
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(enabled = !isLoadingMore, onClick = onLoadMore)
                        .padding(16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    if (isLoadingMore) {
                        CircularProgressIndicator(modifier = Modifier.padding(4.dp))
                    } else {
                        Text("Load older entries")
                    }
                }
            }
            item(key = "load-more-note") {
                Text(
                    text = "Search and filters only apply to loaded entries.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
        }
    }
}

@Composable
private fun ExternalToolBar() {
    val context = LocalContext.current
    val tools = remember { ExternalToolRegistry.all() }
    if (tools.isEmpty()) return

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        tools.forEach { tool ->
            TextButton(onClick = { tool.open(context) }, modifier = Modifier.weight(1f)) {
                Text(tool.title)
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

@Composable
private fun CenteredMessage(text: String, showSpinner: Boolean) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (showSpinner) CircularProgressIndicator()
            Text(text = text, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * Empty state that says what is missing and offers the way out, rather than leaving a blank
 * screen — the difference between "the tool is broken" and "there is nothing here yet".
 */
@Composable
private fun EmptyState(
    title: String,
    detail: String,
    actionLabel: String?,
    onAction: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = OlafIcons.Search,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                modifier = Modifier.size(48.dp)
            )
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            Text(
                text = detail,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            if (actionLabel != null) {
                TextButton(onClick = onAction) { Text(actionLabel) }
            }
        }
    }
}

package com.olaf.ui.view

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.olaf.LogCategory
import com.olaf.LogLevel
import com.olaf.ui.model.NetworkContentKind

/** Bottom sheet holding the level, category and content-type filters. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun LogFilterSheet(
    levels: Set<LogLevel>,
    categories: List<LogCategory>,
    selectedCategories: Set<LogCategory>,
    contentKinds: Set<NetworkContentKind>,
    onToggleLevel: (LogLevel) -> Unit,
    onToggleCategory: (LogCategory) -> Unit,
    onToggleContentKind: (NetworkContentKind) -> Unit,
    onReset: () -> Unit,
    onDismiss: () -> Unit
) {
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
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(title = "Filters", action = "Reset", onAction = onReset)

            FilterSection(title = "Level") {
                LogLevel.entries.forEach { level ->
                    FilterChip(
                        selected = level in levels,
                        onClick = { onToggleLevel(level) },
                        label = { Text("${level.symbol} ${level.name}") }
                    )
                }
            }

            if (categories.isNotEmpty()) {
                FilterSection(title = "Category") {
                    categories.forEach { category ->
                        FilterChip(
                            selected = category in selectedCategories,
                            onClick = { onToggleCategory(category) },
                            label = { Text(category.rawValue) }
                        )
                    }
                }
            }

            FilterSection(title = "Content type") {
                NetworkContentKind.entries.forEach { kind ->
                    FilterChip(
                        selected = kind in contentKinds,
                        onClick = { onToggleContentKind(kind) },
                        label = { Text(kind.title) }
                    )
                }
            }

            Text(
                text = "Selecting a content type hides everything that isn't a network record.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun Row(title: String, action: String, onAction: () -> Unit) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(text = title, style = MaterialTheme.typography.titleMedium)
        TextButton(onClick = onAction) { Text(action) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilterSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            content()
        }
    }
}

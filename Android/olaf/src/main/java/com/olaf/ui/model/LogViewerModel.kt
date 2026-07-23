package com.olaf.ui.model

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.olaf.LogCategory
import com.olaf.LogEntry
import com.olaf.LogLevel
import com.olaf.Olaf
import com.olaf.internal.LogExportFile
import com.olaf.ui.util.HarExporter
import com.olaf.ui.util.PostmanExporter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant

/**
 * State owner for the viewer: merges the instantaneous snapshot with the live stream and applies
 * level/category/content-type/text filtering.
 */
@OptIn(FlowPreview::class)
internal class LogViewerModel : ViewModel() {

    /** Display scope. */
    enum class Scope {
        /** This session — the in-memory ring buffer. */
        SESSION,

        /** The whole on-disk history, including previous sessions. */
        HISTORY
    }

    /** Grouped logs for one app session. */
    data class LogSession(
        val id: String,
        val startedAt: Instant,
        /** Newest first. */
        val entries: List<LogEntry>
    )

    // MARK: - Inputs

    private val _entries = MutableStateFlow<List<LogEntry>>(emptyList())

    private val _scope = MutableStateFlow(Scope.SESSION)
    val scope: StateFlow<Scope> = _scope

    private val _searchText = MutableStateFlow("")
    val searchText: StateFlow<String> = _searchText

    private val _enabledLevels = MutableStateFlow(LogLevel.entries.toSet())
    val enabledLevels: StateFlow<Set<LogLevel>> = _enabledLevels

    private val _selectedCategories = MutableStateFlow(emptySet<LogCategory>())
    val selectedCategories: StateFlow<Set<LogCategory>> = _selectedCategories

    private val _selectedContentKinds = MutableStateFlow(emptySet<NetworkContentKind>())
    val selectedContentKinds: StateFlow<Set<NetworkContentKind>> = _selectedContentKinds

    /** While `true` new logs keep flowing in; `false` freezes the list. */
    private val _isFollowing = MutableStateFlow(true)
    val isFollowing: StateFlow<Boolean> = _isFollowing

    /** Pinned entries, shown in their own section above the list, independent of filters. */
    private val _pinnedIds = MutableStateFlow(emptySet<String>())
    val pinnedIds: StateFlow<Set<String>> = _pinnedIds

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore

    private val _hasMoreHistory = MutableStateFlow(false)
    val hasMoreHistory: StateFlow<Boolean> = _hasMoreHistory

    // MARK: - Internal state

    private var pendingWhilePaused = mutableListOf<LogEntry>()
    private var streamJob: Job? = null
    private var historyCursor: String? = null
    private var appliedDefaultCategory = false

    // MARK: - Derived state

    /** Debounced, normalized search query, so a keystroke doesn't rescan the whole list. */
    private val effectiveQuery: StateFlow<String> = _searchText
        .map { it.trim().lowercase() }
        .distinctUntilChanged()
        .debounce(SEARCH_DEBOUNCE_MS)
        .stateIn(viewModelScope, SharingStarted.Eagerly, "")

    /**
     * Filtered entries plus the decode index, derived in one pass so the two can never disagree —
     * a row hidden by one but not badged by the other would make a decode failure unfindable.
     */
    private val derived: StateFlow<Pair<List<LogEntry>, DecodeAttachmentIndex>> = combine(
        _entries,
        effectiveQuery,
        _enabledLevels,
        _selectedCategories,
        _selectedContentKinds
    ) { entries, query, levels, categories, contentKinds ->
        val index = DecodeAttachmentIndex.build(entries)
        filter(entries, query, levels, categories, contentKinds, index) to index
    }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList<LogEntry>() to DecodeAttachmentIndex.Empty)

    /** Filtered entries, newest first. */
    val filteredEntries: StateFlow<List<LogEntry>> = derived
        .map { it.first }
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    /** Decode errors folded under their network entry. */
    val decodeIndex: StateFlow<DecodeAttachmentIndex> = derived
        .map { it.second }
        .stateIn(viewModelScope, SharingStarted.Eagerly, DecodeAttachmentIndex.Empty)

    /** Categories present in the loaded entries — drives the chip bar. */
    val availableCategories: StateFlow<List<LogCategory>> = _entries
        .map { categoriesIn(it) }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    /** Pinned entries, newest first, independent of the filters. */
    val pinnedEntries: StateFlow<List<LogEntry>> = combine(_entries, _pinnedIds) { entries, ids ->
        if (ids.isEmpty()) emptyList() else entries.asReversed().filter { it.id in ids }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    /** History sessions, excluding the current one — the History tab groups by these. */
    val sessionGroups: StateFlow<List<LogSession>> = filteredEntries
        .map { groupSessions(it, Olaf.currentSessionId) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    /** Is a non-default filter applied? Drives the funnel badge. */
    val isFiltering: StateFlow<Boolean> = combine(
        _enabledLevels,
        _selectedCategories,
        _selectedContentKinds
    ) { levels, categories, contentKinds ->
        levels.size != LogLevel.entries.size || categories.isNotEmpty() || contentKinds.isNotEmpty()
    }.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    // MARK: - Lifecycle

    fun start() {
        reload()
        if (streamJob != null) return
        streamJob = viewModelScope.launch {
            Olaf.stream().collect(::append)
        }
    }

    /**
     * (Re)loads entries for the current scope. Both reads are asynchronous, so the UI thread is
     * never blocked — even while the store is working through a burst. In history mode only the
     * FIRST page is loaded; older pages arrive through [loadOlderHistory].
     */
    fun reload() {
        pendingWhilePaused.clear()
        historyCursor = null
        _hasMoreHistory.value = false
        _isLoadingMore.value = false

        viewModelScope.launch {
            when (_scope.value) {
                Scope.SESSION -> {
                    _entries.value = Olaf.snapshotAsync()
                }

                Scope.HISTORY -> {
                    _isLoading.value = true
                    val page = Olaf.loadPersistedPage(minimumEntries = HISTORY_PAGE_SIZE)
                    _entries.value = page.entries
                    historyCursor = page.nextCursor
                    _hasMoreHistory.value = page.nextCursor != null
                    _isLoading.value = false
                }
            }
            applyDefaultCategorySelection()
        }
    }

    /** Loads the next (older) page of history. A no-op while loading or once history runs out. */
    fun loadOlderHistory() {
        val cursor = historyCursor ?: return
        if (_scope.value != Scope.HISTORY || _isLoading.value || _isLoadingMore.value) return

        _isLoadingMore.value = true
        viewModelScope.launch {
            val page = Olaf.loadPersistedPage(cursor, minimumEntries = HISTORY_PAGE_SIZE)
            // Drop the result if a reload (scope change, clear) landed in the meantime.
            if (_scope.value != Scope.HISTORY || historyCursor != cursor) {
                _isLoadingMore.value = false
                return@launch
            }
            // `_entries` runs oldest to newest, so an older page goes to the FRONT.
            _entries.update { page.entries + it }
            historyCursor = page.nextCursor
            _hasMoreHistory.value = page.nextCursor != null
            _isLoadingMore.value = false
        }
    }

    fun setScope(newScope: Scope) {
        if (newScope == _scope.value) return
        _scope.value = newScope
        reload()
    }

    private fun append(entry: LogEntry) {
        // Live entries aren't mixed into history scope — the current session isn't shown there
        // anyway, and switching back to Session reloads the latest snapshot.
        if (_scope.value == Scope.HISTORY) return

        if (_isFollowing.value) {
            _entries.update { it + entry }
            applyDefaultCategorySelection()
        } else {
            pendingWhilePaused.add(entry)
        }
    }

    fun pauseFollowing() {
        _isFollowing.value = false
    }

    fun resumeFollowing() {
        _isFollowing.value = true
        if (pendingWhilePaused.isNotEmpty()) {
            val flushed = pendingWhilePaused.toList()
            pendingWhilePaused.clear()
            _entries.update { it + flushed }
        }
    }

    /**
     * The viewer opens with the `network` chip preselected — but only once network entries
     * actually exist, because the chip bar only renders categories that were seen: preselecting an
     * unseen one would blank the list behind an invisible filter. Never overrides a user choice.
     */
    private fun applyDefaultCategorySelection() {
        if (appliedDefaultCategory || _selectedCategories.value.isNotEmpty()) return
        val entries = _entries.value
        if (entries.isEmpty()) return
        appliedDefaultCategory = true
        _selectedCategories.value = defaultCategorySelection(entries)
    }

    // MARK: - Actions

    fun setSearchText(value: String) {
        _searchText.value = value
    }

    fun toggleCategory(category: LogCategory) {
        _selectedCategories.update { if (category in it) it - category else it + category }
    }

    fun toggleLevel(level: LogLevel) {
        _enabledLevels.update { if (level in it) it - level else it + level }
    }

    fun toggleContentKind(kind: NetworkContentKind) {
        _selectedContentKinds.update { if (kind in it) it - kind else it + kind }
    }

    fun togglePin(entry: LogEntry) {
        _pinnedIds.update { if (entry.id in it) it - entry.id else it + entry.id }
    }

    fun resetFilters() {
        _enabledLevels.value = LogLevel.entries.toSet()
        _selectedCategories.value = emptySet()
        _selectedContentKinds.value = emptySet()
    }

    fun clear() {
        Olaf.clear()
        _entries.value = emptyList()
        pendingWhilePaused.clear()
        _pinnedIds.value = emptySet()
    }

    // MARK: - Export

    /**
     * Writes the entries **currently on screen** (scope plus every filter) to a shareable file,
     * chronologically — [filteredEntries] is newest first, so it is reversed.
     */
    suspend fun exportLogFile(): File? = Olaf.exportFile(filteredEntries.value.asReversed())

    /** Exports the visible entries as raw NDJSON, for `jq` and other tooling. */
    suspend fun exportNdjsonFile(): File? = Olaf.exportNdjsonFile(filteredEntries.value.asReversed())

    /** Writes the selected entries (multi-select) to a readable `.log` file, chronologically. */
    suspend fun exportSelected(ids: Set<String>): File? {
        val chosen = filteredEntries.value.filter { it.id in ids }.asReversed()
        return if (chosen.isEmpty()) null else Olaf.exportFile(chosen)
    }

    /** Writes the visible **network** entries as HAR 1.2 — opens in Charles/Proxyman/DevTools. */
    suspend fun exportHarFile(cacheDirectory: File): File? = withContext(Dispatchers.IO) {
        val text = HarExporter.harDocument(filteredEntries.value.asReversed())
        LogExportFile.write(cacheDirectory, text, fileExtension = "har")
    }

    /** Writes the visible **network** entries as a Postman Collection v2.1. */
    suspend fun exportPostmanFile(cacheDirectory: File): File? = withContext(Dispatchers.IO) {
        val text = PostmanExporter.collection(filteredEntries.value.asReversed())
        LogExportFile.write(cacheDirectory, text, fileExtension = "postman_collection.json")
    }

    /** Statistics over the entries currently on screen. */
    fun statistics(): NetworkStats = NetworkStats.compute(filteredEntries.value)

    // MARK: - Derivation logic (pure functions → directly testable)

    internal companion object {
        private const val SEARCH_DEBOUNCE_MS = 200L
        private const val HISTORY_PAGE_SIZE = 500

        /**
         * Level/category/content-type/search filter — newest first.
         *
         * An attached decode entry is never listed on its own; its network row answers for it
         * instead, matching the `decoding` chip, the `ERROR` level and any query that hits the
         * attached entry — so folding never makes a decode failure unfindable.
         */
        fun filter(
            entries: List<LogEntry>,
            query: String, // already trimmed and lowercased by the debounce pipeline
            levels: Set<LogLevel>,
            categories: Set<LogCategory>,
            contentKinds: Set<NetworkContentKind> = emptySet(),
            decodeIndex: DecodeAttachmentIndex = DecodeAttachmentIndex.Empty
        ): List<LogEntry> = entries.asReversed().filter { entry ->
            if (entry.id in decodeIndex.attachedIds) return@filter false
            val attached = decodeIndex.errors(entry)

            if (levels.isNotEmpty() && entry.level !in levels) {
                if (attached.isEmpty() || LogLevel.ERROR !in levels) return@filter false
            }
            if (categories.isNotEmpty() && entry.category !in categories) {
                if (attached.isEmpty() || LogCategory.Decoding !in categories) return@filter false
            }
            if (contentKinds.isNotEmpty()) {
                val kind = NetworkContentKind.of(entry)
                if (kind == null || kind !in contentKinds) return@filter false
            }
            query.isEmpty() || matchesQuery(entry, query) || attached.any { matchesQuery(it, query) }
        }

        fun matchesQuery(entry: LogEntry, query: String): Boolean {
            if (entry.message.lowercase().contains(query)) return true
            if (entry.category.rawValue.lowercase().contains(query)) return true
            return entry.metadata.any { (key, value) ->
                key.lowercase().contains(query) || value.lowercase().contains(query)
            }
        }

        /**
         * Groups entries by session, skipping [current]. Sessions come back newest first, and so
         * do the entries within each one.
         */
        fun groupSessions(entries: List<LogEntry>, current: String): List<LogSession> {
            val grouped = LinkedHashMap<String, MutableList<LogEntry>>()
            for (entry in entries) {
                if (entry.sessionId == current) continue
                grouped.getOrPut(entry.sessionId) { mutableListOf() }.add(entry)
            }
            return grouped.map { (id, items) ->
                LogSession(
                    id = id,
                    startedAt = items.minOf { it.date },
                    entries = items
                )
            }.sortedByDescending { it.startedAt }
        }

        /** `network` is preselected when network entries exist, nothing otherwise. */
        fun defaultCategorySelection(entries: List<LogEntry>): Set<LogCategory> =
            if (entries.any { it.category == LogCategory.Network }) setOf(LogCategory.Network) else emptySet()

        /** Categories seen in the entries, deduplicated and sorted by name. */
        fun categoriesIn(entries: List<LogEntry>): List<LogCategory> =
            entries.mapTo(LinkedHashSet()) { it.category }.sortedBy { it.rawValue }
    }
}

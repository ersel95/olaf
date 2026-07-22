import Foundation
import Combine

/// State owner for the viewer: merges the instantaneous snapshot with the live stream, and applies
/// level/category/text filtering.
@MainActor
public final class LogViewerModel: ObservableObject {

    /// All collected entries (snapshot + live).
    @Published public private(set) var entries: [LogEntry] = []

    /// Display scope.
    public enum Scope: String, CaseIterable, Sendable {
        case session   // this session (in-memory ring buffer)
        case history   // entire disk history (including previous sessions)
    }
    @Published public var scope: Scope = .session

    /// Filters.
    @Published public var searchText: String = ""
    /// Debounced, normalized (trim + lowercase) form of `searchText`. Updated not on every
    /// keystroke, but after the user stops typing → we don't scan the whole list on every
    /// keystroke. `filteredEntries` uses this.
    @Published private var effectiveQuery: String = ""
    /// Levels to display (multi-select). Empty = all.
    @Published public var enabledLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @Published public var selectedCategories: Set<LogCategory> = []
    /// Network content-type filter (empty = off). When selected, **only** network entries of
    /// these types are shown (non-network entries are hidden).
    @Published public var selectedContentKinds: Set<NetworkContentKind> = []

    /// `true` while new logs are appended live; `false` (paused) freezes the list.
    @Published public var isFollowing: Bool = true

    /// Pinned entry identifiers (per-session; not persisted). Pins are shown in a separate
    /// section at the top of the list, **independent of filters**.
    @Published public var pinnedIDs: Set<UUID> = []

    private var pendingWhilePaused: [LogEntry] = []
    private var streamTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Live-stream coalescing buffer: incoming entries aren't appended to `entries` one at a
    /// time (each append triggers an `@Published` emission → a full SwiftUI diff + recomputing
    /// `filteredEntries`); instead they accumulate here and are flushed **in bulk** at a short
    /// interval. This significantly reduces main-thread churn under heavy logging (network capture).
    private var incoming: [LogEntry] = []
    private var flushScheduled = false
    private static let coalesceInterval: UInt64 = 100_000_000  // 100 ms

    /// `true` while history (disk) is loading.
    @Published public private(set) var isLoading: Bool = false

    // MARK: - History pagination
    //
    // History is now loaded page by page (newest to oldest) rather than all at once. Filter/search
    // only operates on LOADED entries; as the user scrolls (or taps the button), older pages are
    // appended to the end of the list.

    /// Is there an older, not-yet-loaded page on disk?
    @Published public private(set) var hasMoreHistory: Bool = false
    /// `true` while an older page is loading (the row below the list shows a spinner).
    @Published public private(set) var isLoadingMore: Bool = false
    /// Cursor for the next (older) page.
    private var historyCursor: String?
    /// Target minimum entry count per page.
    private static let historyPageSize = 500

    // MARK: - Derived (memoized) state
    //
    // These used to be computed properties → the entire list was rescanned on every SwiftUI
    // render (stutter with large History). Now they are computed once, only when the inputs
    // change, and published via @Published.

    /// Filtered entries, sorted newest first.
    @Published public private(set) var filteredEntries: [LogEntry] = []

    /// Decode errors folded under their network entry (list shows a badge on the
    /// network row instead of one row per decode error; detail lists them all).
    @Published private(set) var decodeIndex: DecodeAttachmentIndex = .empty

    /// Session groups for history entries — **excluding the current session** (shown in the "Session" tab).
    @Published public private(set) var sessionGroups: [LogSession] = []

    /// Categories seen in the current entries (for the filter bar).
    @Published public private(set) var availableCategories: [LogCategory] = []

    public init() {
        // Search debounce: searchText → (trim+lowercase) → 200ms of silence → effectiveQuery.
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .assign(to: &$effectiveQuery)

        // Values derived from inputs: computed only when an input changes (not per render).
        // The decode index is built in the same pass as the filter so the two published
        // values can never disagree (a row hidden by one but not badged by the other).
        let categorySelection = Publishers.CombineLatest($selectedCategories, $selectedContentKinds)
        let derived = Publishers.CombineLatest4($entries, $effectiveQuery, $enabledLevels, categorySelection)
            .map { entries, query, levels, selection -> (filtered: [LogEntry], index: DecodeAttachmentIndex) in
                let index = DecodeAttachmentIndex.build(from: entries)
                let filtered = Self.filter(
                    entries: entries, query: query, levels: levels,
                    categories: selection.0, contentKinds: selection.1,
                    decodeIndex: index
                )
                return (filtered, index)
            }
            .share()
        derived.map(\.filtered).assign(to: &$filteredEntries)
        derived.map(\.index).assign(to: &$decodeIndex)

        $filteredEntries
            .map { Self.groupSessions($0, excluding: Olaf.currentSessionID) }
            .assign(to: &$sessionGroups)

        $entries
            .map { Self.categories(in: $0) }
            .removeDuplicates()
            .assign(to: &$availableCategories)

        // Default filter: the viewer opens with the network category preselected — but only
        // when network entries actually exist, because the chip bar only renders seen
        // categories: preselecting an unseen one would blank the list behind an invisible,
        // chipless filter. Applied once, on the first non-empty load, and never over a
        // selection the user already made.
        $entries
            .filter { !$0.isEmpty }
            .first()
            .sink { [weak self] entries in
                guard let self, self.selectedCategories.isEmpty else { return }
                self.selectedCategories = Self.defaultCategorySelection(for: entries)
            }
            .store(in: &cancellables)
    }

    deinit { streamTask?.cancel() }

    // MARK: - Lifecycle

    public func start() {
        reload()
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            for await entry in Olaf.stream() {
                guard let self else { return }
                self.append(entry)
            }
        }
    }

    /// (Re)loads entries according to scope. In both session (memory) and history (disk) mode,
    /// reading is done **asynchronously** → the UI/main thread never blocks (even under heavy
    /// core-queue load). In history mode only the FIRST page is loaded; the rest comes via `loadOlderHistory()`.
    public func reload() {
        pendingWhilePaused.removeAll()
        incoming.removeAll()
        historyCursor = nil
        hasMoreHistory = false
        isLoadingMore = false
        switch scope {
        case .session:
            Task { [weak self] in
                let snapshot = await Olaf.snapshotAsync()
                guard let self else { return }
                self.entries = snapshot
            }
        case .history:
            isLoading = true
            Task { [weak self] in
                let page = await Olaf.loadPersistedPage(minimumEntries: Self.historyPageSize)
                guard let self else { return }
                self.entries = page.entries
                self.historyCursor = page.nextCursor
                self.hasMoreHistory = page.nextCursor != nil
                self.isLoading = false
            }
        }
    }

    /// Loads the next (older) page of history and appends it to the end of the list.
    /// Idempotent: calls are a no-op while loading, or when there is no cursor.
    public func loadOlderHistory() {
        guard scope == .history, !isLoading, !isLoadingMore, let cursor = historyCursor else { return }
        isLoadingMore = true
        Task { [weak self] in
            let page = await Olaf.loadPersistedPage(before: cursor, minimumEntries: Self.historyPageSize)
            guard let self else { return }
            // Don't apply the result if the page was reset by a reload in the meantime (scope change, etc).
            guard self.scope == .history, self.historyCursor == cursor else {
                self.isLoadingMore = false
                return
            }
            // `entries` is kept oldest-to-newest; the older page is inserted at the FRONT.
            self.entries.insert(contentsOf: page.entries, at: 0)
            self.historyCursor = page.nextCursor
            self.hasMoreHistory = page.nextCursor != nil
            self.isLoadingMore = false
        }
    }

    public func setScope(_ newScope: Scope) {
        guard newScope != scope else { return }
        scope = newScope
        reload()
    }

    private func append(_ entry: LogEntry) {
        incoming.append(entry)
        scheduleFlush()
    }

    /// Flushes the accumulated `incoming` entries **all at once** after a short delay (coalescing).
    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.coalesceInterval)
            guard let self else { return }
            self.flushScheduled = false
            guard !self.incoming.isEmpty else { return }
            // Live entries are not mixed into the list while in history scope (the current
            // session isn't shown there anyway); reload() picks up the latest snapshot when
            // returning to Session — nothing is lost.
            if self.scope == .history {
                self.incoming.removeAll(keepingCapacity: true)
                return
            }
            // If paused, entries wait until "resume" (pause semantics preserved).
            if self.isFollowing {
                self.entries.append(contentsOf: self.incoming)
            } else {
                self.pendingWhilePaused.append(contentsOf: self.incoming)
            }
            self.incoming.removeAll(keepingCapacity: true)
        }
    }

    public func resumeFollowing() {
        isFollowing = true
        if !pendingWhilePaused.isEmpty {
            entries.append(contentsOf: pendingWhilePaused)
            pendingWhilePaused.removeAll()
        }
    }

    // MARK: - Derivation logic (pure functions → testable)

    /// Grouped logs for one app session.
    public struct LogSession: Identifiable, Sendable {
        public let id: String        // sessionID
        public let startDate: Date   // earliest entry in the session
        public let entries: [LogEntry]  // newest first
    }

    /// Level/category/content-type/search filter — newest first.
    ///
    /// Decode entries attached to a network entry are never listed as rows; their
    /// network entry answers for them instead: it matches the `.decoding` category
    /// chip, the `.error` level filter, and search queries that hit an attached
    /// entry — so folding never makes a decode failure unfindable.
    nonisolated static func filter(
        entries: [LogEntry],
        query: String,   // already trim+lowercase (from the debounce pipeline)
        levels: Set<LogLevel>,
        categories: Set<LogCategory>,
        contentKinds: Set<NetworkContentKind> = [],
        decodeIndex: DecodeAttachmentIndex = .empty
    ) -> [LogEntry] {
        entries.reversed().filter { entry in
            if decodeIndex.attachedIDs.contains(entry.id) { return false }
            let attachedErrors = decodeIndex.errors(for: entry)
            if !levels.isEmpty, !levels.contains(entry.level) {
                guard !attachedErrors.isEmpty, levels.contains(.error) else { return false }
            }
            if !categories.isEmpty, !categories.contains(entry.category) {
                guard !attachedErrors.isEmpty, categories.contains(.decoding) else { return false }
            }
            if !contentKinds.isEmpty {
                guard let kind = NetworkContentKind.of(entry), contentKinds.contains(kind) else {
                    return false
                }
            }
            guard !query.isEmpty else { return true }
            return matchesQuery(entry, query) || attachedErrors.contains { matchesQuery($0, query) }
        }
    }

    nonisolated private static func matchesQuery(_ entry: LogEntry, _ query: String) -> Bool {
        if entry.message.lowercased().contains(query) { return true }
        if entry.category.rawValue.lowercased().contains(query) { return true }
        return entry.metadata.contains { key, value in
            key.lowercased().contains(query) || value.lowercased().contains(query)
        }
    }

    /// Groups entries by session; `excluding` (the current session) is skipped.
    /// Sessions are sorted newest to oldest; their contents are newest first.
    nonisolated static func groupSessions(_ entries: [LogEntry], excluding current: String) -> [LogSession] {
        var grouped: [String: [LogEntry]] = [:]
        var order: [String] = []
        for entry in entries where entry.sessionID != current {
            if grouped[entry.sessionID] == nil { order.append(entry.sessionID) }
            grouped[entry.sessionID, default: []].append(entry)
        }
        return order
            .map { id in
                let items = grouped[id] ?? []
                let start = items.map(\.date).min() ?? .distantPast
                return LogSession(id: id, startDate: start, entries: items)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Initial category selection for a fresh viewer: `.network` preselected when network
    /// entries exist, nothing otherwise (all categories shown).
    nonisolated static func defaultCategorySelection(for entries: [LogEntry]) -> Set<LogCategory> {
        entries.contains { $0.category == .network } ? [.network] : []
    }

    /// Categories seen in the entries (sorted by name, deduplicated).
    nonisolated static func categories(in entries: [LogEntry]) -> [LogCategory] {
        var seen = Set<LogCategory>()
        var ordered: [LogCategory] = []
        for entry in entries where !seen.contains(entry.category) {
            seen.insert(entry.category)
            ordered.append(entry.category)
        }
        return ordered.sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Actions

    public func toggleCategory(_ category: LogCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    public func toggleLevel(_ level: LogLevel) {
        if enabledLevels.contains(level) {
            enabledLevels.remove(level)
        } else {
            enabledLevels.insert(level)
        }
    }

    public func togglePin(_ entry: LogEntry) {
        if pinnedIDs.contains(entry.id) {
            pinnedIDs.remove(entry.id)
        } else {
            pinnedIDs.insert(entry.id)
        }
    }

    /// Pinned entries (newest first) — independent of filters, from among the loaded entries.
    public var pinnedEntries: [LogEntry] {
        Self.pinned(in: entries, ids: pinnedIDs)
    }

    nonisolated static func pinned(in entries: [LogEntry], ids: Set<UUID>) -> [LogEntry] {
        guard !ids.isEmpty else { return [] }
        return entries.reversed().filter { ids.contains($0.id) }
    }

    /// Writes the selected entries (multi-select) to a readable `.log` file — in chronological order.
    public func exportFileURL(for ids: Set<UUID>) async -> URL? {
        let chosen = Array(filteredEntries.filter { ids.contains($0.id) }.reversed())
        guard !chosen.isEmpty else { return nil }
        return await Olaf.exportFileURL(entries: chosen)
    }

    public func toggleContentKind(_ kind: NetworkContentKind) {
        if selectedContentKinds.contains(kind) {
            selectedContentKinds.remove(kind)
        } else {
            selectedContentKinds.insert(kind)
        }
    }

    /// Is a non-default filter applied? (shown in the funnel badge)
    public var isFiltering: Bool {
        enabledLevels.count != LogLevel.allCases.count
            || !selectedCategories.isEmpty
            || !selectedContentKinds.isEmpty
    }

    public func resetFilters() {
        enabledLevels = Set(LogLevel.allCases)
        selectedCategories.removeAll()
        selectedContentKinds.removeAll()
    }

    public func clear() {
        Olaf.clear()
        entries.removeAll()
        pendingWhilePaused.removeAll()
        incoming.removeAll()
        pinnedIDs.removeAll()
    }

    /// Writes the entries **currently visible on screen** (scope + level/category/search filters
    /// applied) to a shareable file. If no filter is selected, this equals the entire visible
    /// list. Written chronologically (oldest → newest); `filteredEntries` is sorted newest first.
    public func exportFileURL() async -> URL? {
        let visible = Array(filteredEntries.reversed())
        return await Olaf.exportFileURL(entries: visible)
    }

    /// Exports the visible entries as **raw NDJSON** (for jq/backend analysis).
    public func exportNDJSONFileURL() async -> URL? {
        let visible = Array(filteredEntries.reversed())
        return await Olaf.exportNDJSONFileURL(entries: visible)
    }

    /// Writes the visible **network** entries to a HAR 1.2 file (opens in Charles/Proxyman/DevTools).
    public func exportHARFileURL() async -> URL? {
        let visible = Array(filteredEntries.reversed())
        return await Task.detached(priority: .utility) {
            guard let text = HARExporter.harDocument(from: visible) else { return nil }
            return LogExportFile.write(text, fileExtension: "har")
        }.value
    }

    /// Writes the visible **network** entries to a Postman Collection v2.1 file
    /// (same method+URL once; can be re-run via Postman → Import).
    public func exportPostmanFileURL() async -> URL? {
        let visible = Array(filteredEntries.reversed())
        return await Task.detached(priority: .utility) {
            guard let text = PostmanExporter.collection(from: visible) else { return nil }
            return LogExportFile.write(text, fileExtension: "postman_collection.json")
        }.value
    }

    /// Registered external tools (switch-to buttons).
    public var externalTools: [any ExternalToolBridge] {
        ExternalToolRegistry.shared.all
    }
}

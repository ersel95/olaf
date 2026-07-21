#if canImport(UIKit)
import SwiftUI

/// Root screen of the Olaf in-app viewer. Opens when the device is shaken.
public struct OlafViewerView: View {

    @StateObject private var model = LogViewerModel()
    private let onClose: () -> Void

    @State private var isFilterPresented = false
    @State private var isStatsPresented = false
    @State private var isMocksPresented = false
    /// Multi-select mode (Session scope only).
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()

    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scopePicker
                FilterBarView(model: model)
                if model.scope == .session {
                    PendingRequestsBar()
                }
                Divider()
                logList
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search logs")
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { externalToolBar }
            .sheet(isPresented: $isFilterPresented) {
                LogFilterView(model: model)
            }
            .sheet(isPresented: $isStatsPresented) {
                NetworkStatsView(entries: model.filteredEntries)
            }
            .sheet(isPresented: $isMocksPresented) {
                MockListView()
            }
        }
        .onAppear { model.start() }
    }

    private var scopePicker: some View {
        Picker("Scope", selection: Binding(
            get: { model.scope },
            set: { model.setScope($0) }
        )) {
            Text("Session").tag(LogViewerModel.Scope.session)
            Text("History").tag(LogViewerModel.Scope.history)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - List

    @ViewBuilder
    private var logList: some View {
        if model.isLoading {
            ProgressView("Loading history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.scope == .history {
            historyList
        } else {
            sessionList
        }
    }

    /// Current session — pins on top, flat list (newest first), multi-select supported.
    @ViewBuilder
    private var sessionList: some View {
        let entries = model.filteredEntries
        if entries.isEmpty && model.pinnedEntries.isEmpty {
            ContentUnavailableView("No entries", systemImage: "doc.text.magnifyingglass", description: Text("No logs matched the filter."))
                .frame(maxHeight: .infinity)
        } else {
            List(selection: $selectedIDs) {
                if !model.pinnedEntries.isEmpty && !isSelecting {
                    pinnedSection
                }
                Section {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) { logRow(entry) }
                            .contextMenu { pinButton(entry) }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
            .navigationDestination(for: LogEntry.self) { entry in
                LogDetailView(entry: entry, decodeErrors: model.decodeIndex.errors(for: entry))
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
            }
        }
    }

    /// Pinned entries — independent of filters, at the top of the list.
    private var pinnedSection: some View {
        Section {
            ForEach(model.pinnedEntries) { entry in
                NavigationLink(value: entry) { logRow(entry) }
                    .contextMenu { pinButton(entry) }
            }
        } header: {
            Label("Pinned", systemImage: "pin.fill")
                .font(.caption)
        }
    }

    /// Row with the folded decode-error badge (count comes from the shared index).
    private func logRow(_ entry: LogEntry) -> some View {
        LogRowView(entry: entry, decodeErrorCount: model.decodeIndex.errors(for: entry).count)
    }

    private func pinButton(_ entry: LogEntry) -> some View {
        let isPinned = model.pinnedIDs.contains(entry.id)
        return Button {
            model.togglePin(entry)
        } label: {
            Label(isPinned ? "Unpin" : "Pin",
                  systemImage: isPinned ? "pin.slash" : "pin")
        }
    }

    /// Bottom share bar shown in multi-select mode.
    private var selectionBar: some View {
        HStack {
            Text("\(selectedIDs.count) entries selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                shareSelected()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func shareSelected() {
        Task {
            if let url = await model.exportFileURL(for: selectedIDs) {
                presentShareSheet([url])
            }
        }
    }

    /// History — grouped by previous sessions (each session is a section), paginated.
    @ViewBuilder
    private var historyList: some View {
        let sessions = model.sessionGroups
        if sessions.isEmpty && !model.hasMoreHistory {
            ContentUnavailableView("No history sessions", systemImage: "clock.arrow.circlepath", description: Text("No logs found from previous sessions."))
                .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(sessions) { session in
                    Section {
                        ForEach(session.entries) { entry in
                            NavigationLink(value: entry) { logRow(entry) }
                        }
                    } header: {
                        sessionHeader(session)
                    }
                }
                if model.hasMoreHistory {
                    loadMoreSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationDestination(for: LogEntry.self) { entry in
                LogDetailView(entry: entry, decodeErrors: model.decodeIndex.errors(for: entry))
            }
        }
    }

    /// Automatically loads an older page when it appears at the end of the list (infinite
    /// scroll); the button offers a manual fallback if the automatic trigger is missed.
    private var loadMoreSection: some View {
        Section {
            Button {
                model.loadOlderHistory()
            } label: {
                HStack {
                    Spacer()
                    if model.isLoadingMore {
                        ProgressView()
                    } else {
                        Label("Load older entries", systemImage: "arrow.down.circle")
                    }
                    Spacer()
                }
            }
            .disabled(model.isLoadingMore)
            .onAppear { model.loadOlderHistory() }
        } footer: {
            Text("Search and filters only apply to loaded entries.")
                .font(.caption2)
        }
    }

    private func sessionHeader(_ session: LogViewerModel.LogSession) -> some View {
        HStack {
            Label(session.startDate.formatted(date: .abbreviated, time: .standard), systemImage: "clock")
            Spacer()
            Text("\(session.entries.count) entries")
        }
        .font(.caption)
        .textCase(nil)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close") { onClose() }
        }
        ToolbarItem(placement: .principal) {
            Image("OlafLogo", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .foregroundStyle(.primary)
                .accessibilityLabel("Olaf")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isFilterPresented = true
            } label: {
                Image(systemName: model.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filters")
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button("Done") {
                    isSelecting = false
                    selectedIDs.removeAll()
                }
            } else {
                Menu {
                    followToggle
                    if model.scope == .session {
                        Button { isSelecting = true } label: { Label("Select", systemImage: "checkmark.circle") }
                    }
                    Divider()
                    shareMenu
                    Button { isStatsPresented = true } label: { Label("Statistics", systemImage: "chart.bar") }
                    Button { isMocksPresented = true } label: { Label("Mocks", systemImage: "arrow.triangle.2.circlepath") }
                    Divider()
                    Button { importOSLog() } label: { Label("Import OSLog (1 hour)", systemImage: "square.and.arrow.down") }
                    Button(role: .destructive) { model.clear() } label: { Label("Clear", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var followToggle: some View {
        if model.isFollowing {
            Button { model.isFollowing = false } label: { Label("Pause", systemImage: "pause.fill") }
        } else {
            Button { model.resumeFollowing() } label: { Label("Resume", systemImage: "play.fill") }
        }
    }

    /// A prominent bottom bar, always visible on the main screen, for switching to registered
    /// external tools with a single tap. Not shown at all if no tool is registered.
    @ViewBuilder
    private var externalToolBar: some View {
        let tools = model.externalTools
        if !tools.isEmpty {
            HStack(spacing: 12) {
                ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                    Button {
                        tool.open()
                    } label: {
                        Label(tool.title, systemImage: tool.systemImage ?? "arrow.up.right.square")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    /// Share-format submenu (over the visible — filtered — entries).
    private var shareMenu: some View {
        Menu {
            Button { share(.log) } label: { Label(".log (plain text)", systemImage: "doc.text") }
            Button { share(.ndjson) } label: { Label("NDJSON (raw)", systemImage: "curlybraces.square") }
            Button { share(.har) } label: { Label("HAR (network)", systemImage: "network") }
            Button { share(.postman) } label: { Label("Postman Collection", systemImage: "paperplane") }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private enum ExportKind { case log, ndjson, har, postman }

    private func share(_ kind: ExportKind) {
        Task {
            let url: URL?
            switch kind {
            case .log: url = await model.exportFileURL()
            case .ndjson: url = await model.exportNDJSONFileURL()
            case .har: url = await model.exportHARFileURL()
            case .postman: url = await model.exportPostmanFileURL()
            }
            if let url {
                presentShareSheet([url])
            }
        }
    }

    /// Imports the last 1 hour of OSLog entries (including os_log output from other SDKs).
    private func importOSLog() {
        Task {
            _ = try? await Olaf.importOSLogEntries(since: Date().addingTimeInterval(-3600))
            model.reload()
        }
    }

}
#endif

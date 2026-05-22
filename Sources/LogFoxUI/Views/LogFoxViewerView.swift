#if canImport(UIKit)
import SwiftUI
import LogFoxCore

/// LogFox in-app viewer kök ekranı. Cihaz sallandığında bu açılır.
public struct LogFoxViewerView: View {

    @StateObject private var model = LogViewerModel()
    private let onClose: () -> Void

    @State private var shareURL: URL?
    @State private var isSharePresented = false

    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scopePicker
                FilterBarView(model: model)
                Divider()
                logList
            }
            .navigationTitle("LogFox")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Loglarda ara")
            .toolbar { toolbarContent }
            .sheet(isPresented: $isSharePresented) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
        }
        .onAppear { model.start() }
    }

    private var scopePicker: some View {
        Picker("Kapsam", selection: Binding(
            get: { model.scope },
            set: { model.setScope($0) }
        )) {
            Text("Oturum").tag(LogViewerModel.Scope.session)
            Text("Geçmiş").tag(LogViewerModel.Scope.history)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Liste

    @ViewBuilder
    private var logList: some View {
        let entries = model.filteredEntries
        if entries.isEmpty {
            ContentUnavailableView("Kayıt yok", systemImage: "doc.text.magnifyingglass", description: Text("Filtreyle eşleşen log bulunamadı."))
                .frame(maxHeight: .infinity)
        } else {
            List(entries) { entry in
                NavigationLink(value: entry) {
                    LogRowView(entry: entry)
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: LogEntry.self) { LogDetailView(entry: $0) }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Kapat") { onClose() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                levelMenu
                followToggle
                Divider()
                externalToolButtons
                Divider()
                Button { share() } label: { Label("Paylaş", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { model.clear() } label: { Label("Temizle", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var levelMenu: some View {
        Picker("Min. Seviye", selection: $model.minimumLevel) {
            ForEach(LogLevel.allCases, id: \.self) { level in
                Text("\(level.symbol) \(level.name)").tag(level)
            }
        }
    }

    @ViewBuilder
    private var followToggle: some View {
        if model.isFollowing {
            Button { model.isFollowing = false } label: { Label("Duraklat", systemImage: "pause.fill") }
        } else {
            Button { model.resumeFollowing() } label: { Label("Devam et", systemImage: "play.fill") }
        }
    }

    @ViewBuilder
    private var externalToolButtons: some View {
        ForEach(Array(model.externalTools.enumerated()), id: \.offset) { _, tool in
            Button {
                tool.open()
            } label: {
                Label(tool.title, systemImage: tool.systemImage ?? "arrow.up.right.square")
            }
        }
    }

    private func share() {
        guard let url = model.exportFileURL() else { return }
        shareURL = url
        isSharePresented = true
    }
}
#endif

#if canImport(UIKit)
import SwiftUI

/// Olaf in-app viewer kök ekranı. Cihaz sallandığında bu açılır.
public struct OlafViewerView: View {

    @StateObject private var model = LogViewerModel()
    private let onClose: () -> Void

    @State private var isFilterPresented = false
    @State private var isStatsPresented = false

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
            .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Loglarda ara")
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { externalToolBar }
            .sheet(isPresented: $isFilterPresented) {
                LogFilterView(model: model)
            }
            .sheet(isPresented: $isStatsPresented) {
                NetworkStatsView(entries: model.filteredEntries)
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
        if model.isLoading {
            ProgressView("Geçmiş yükleniyor…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.scope == .history {
            historyList
        } else {
            sessionList
        }
    }

    /// Mevcut oturum — düz liste (en yeni üstte).
    @ViewBuilder
    private var sessionList: some View {
        let entries = model.filteredEntries
        if entries.isEmpty {
            ContentUnavailableView("Kayıt yok", systemImage: "doc.text.magnifyingglass", description: Text("Filtreyle eşleşen log bulunamadı."))
                .frame(maxHeight: .infinity)
        } else {
            List(entries) { entry in
                NavigationLink(value: entry) { LogRowView(entry: entry) }
            }
            .listStyle(.plain)
            .navigationDestination(for: LogEntry.self) { LogDetailView(entry: $0) }
        }
    }

    /// Geçmiş — önceki oturumlara göre gruplanmış (her oturum bir bölüm), sayfalı.
    @ViewBuilder
    private var historyList: some View {
        let sessions = model.sessionGroups
        if sessions.isEmpty && !model.hasMoreHistory {
            ContentUnavailableView("Geçmiş oturum yok", systemImage: "clock.arrow.circlepath", description: Text("Önceki oturumlardan log bulunamadı."))
                .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(sessions) { session in
                    Section {
                        ForEach(session.entries) { entry in
                            NavigationLink(value: entry) { LogRowView(entry: entry) }
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
            .navigationDestination(for: LogEntry.self) { LogDetailView(entry: $0) }
        }
    }

    /// Liste sonunda görününce otomatik daha eski sayfayı yükler (sonsuz kaydırma);
    /// buton, otomatik tetikleme kaçarsa el ile devam imkânı verir.
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
                        Label("Daha eskileri yükle", systemImage: "arrow.down.circle")
                    }
                    Spacer()
                }
            }
            .disabled(model.isLoadingMore)
            .onAppear { model.loadOlderHistory() }
        } footer: {
            Text("Arama ve filtreler yalnız yüklenen kayıtlarda çalışır.")
                .font(.caption2)
        }
    }

    private func sessionHeader(_ session: LogViewerModel.LogSession) -> some View {
        HStack {
            Label(session.startDate.formatted(date: .abbreviated, time: .standard), systemImage: "clock")
            Spacer()
            Text("\(session.entries.count) kayıt")
        }
        .font(.caption)
        .textCase(nil)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Kapat") { onClose() }
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
            .accessibilityLabel("Filtreler")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                followToggle
                Divider()
                shareMenu
                Button { isStatsPresented = true } label: { Label("İstatistikler", systemImage: "chart.bar") }
                Divider()
                Button { importOSLog() } label: { Label("OSLog'u içe aktar (1 saat)", systemImage: "square.and.arrow.down") }
                Button(role: .destructive) { model.clear() } label: { Label("Temizle", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
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

    /// Ana ekranda her zaman görünen, kayıtlı dış araçlara tek dokunuşla
    /// geçiş için belirgin alt bar. Kayıtlı araç yoksa hiç görünmez.
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

    /// Paylaşım biçimleri alt menüsü (görünen — filtreli — kayıtlar üzerinden).
    private var shareMenu: some View {
        Menu {
            Button { share(.log) } label: { Label(".log (düz metin)", systemImage: "doc.text") }
            Button { share(.ndjson) } label: { Label("NDJSON (ham)", systemImage: "curlybraces.square") }
            Button { share(.har) } label: { Label("HAR (network)", systemImage: "network") }
            Button { share(.postman) } label: { Label("Postman Collection", systemImage: "paperplane") }
        } label: {
            Label("Paylaş", systemImage: "square.and.arrow.up")
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

    /// Son 1 saatin OSLog kayıtlarını (diğer SDK'ların os_log çıktıları dahil) içe aktarır.
    private func importOSLog() {
        Task {
            _ = try? await Olaf.importOSLogEntries(since: Date().addingTimeInterval(-3600))
            model.reload()
        }
    }

}
#endif

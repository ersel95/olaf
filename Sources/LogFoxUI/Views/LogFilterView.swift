#if canImport(UIKit)
import SwiftUI
import LogFoxCore

/// Filtre ekranı: seviye ve kategori toggle'ları.
struct LogFilterView: View {
    @ObservedObject var model: LogViewerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Kapsam") {
                    Picker("Kayıtlar", selection: Binding(
                        get: { model.scope },
                        set: { model.setScope($0) }
                    )) {
                        Text("Bu oturum").tag(LogViewerModel.Scope.session)
                        Text("Tüm geçmiş").tag(LogViewerModel.Scope.history)
                    }
                }

                Section {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Toggle(isOn: Binding(
                            get: { model.enabledLevels.contains(level) },
                            set: { _ in model.toggleLevel(level) }
                        )) {
                            HStack(spacing: 8) {
                                LevelDot(level: level)
                                Text(level.name).font(.callout)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Seviyeler")
                        Spacer()
                        Button(allLevelsOn ? "Hiçbiri" : "Tümü") { toggleAllLevels() }
                            .font(.caption)
                            .textCase(nil)
                    }
                }

                let categories = model.availableCategories
                if !categories.isEmpty {
                    Section("Kategoriler") {
                        ForEach(categories, id: \.self) { category in
                            Toggle(isOn: Binding(
                                get: { model.selectedCategories.isEmpty || model.selectedCategories.contains(category) },
                                set: { _ in model.toggleCategory(category) }
                            )) {
                                Text(category.rawValue).font(.callout)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filtreler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sıfırla") { model.resetFilters() }
                        .disabled(!model.isFiltering)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private var allLevelsOn: Bool {
        model.enabledLevels.count == LogLevel.allCases.count
    }

    private func toggleAllLevels() {
        model.enabledLevels = allLevelsOn ? [] : Set(LogLevel.allCases)
    }
}
#endif

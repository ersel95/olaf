#if canImport(UIKit)
import SwiftUI

/// Filter screen: level and category toggles.
struct LogFilterView: View {
    @ObservedObject var model: LogViewerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Scope") {
                    Picker("Entries", selection: Binding(
                        get: { model.scope },
                        set: { model.setScope($0) }
                    )) {
                        Text("This session").tag(LogViewerModel.Scope.session)
                        Text("All history").tag(LogViewerModel.Scope.history)
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
                        Text("Levels")
                        Spacer()
                        Button(allLevelsOn ? "None" : "All") { toggleAllLevels() }
                            .font(.caption)
                            .textCase(nil)
                    }
                }

                Section {
                    Picker("Threshold", selection: Binding(
                        get: { Olaf.minimumLevel },
                        set: { Olaf.minimumLevel = $0 }
                    )) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.name).tag(level)
                        }
                    }
                } header: {
                    Text("Collection threshold")
                } footer: {
                    Text("Levels below the threshold are never collected (independent of the display filters above; reverts to the config value on app restart).")
                }

                Section {
                    ForEach(NetworkContentKind.allCases, id: \.self) { kind in
                        Toggle(isOn: Binding(
                            get: { model.selectedContentKinds.isEmpty || model.selectedContentKinds.contains(kind) },
                            set: { _ in model.toggleContentKind(kind) }
                        )) {
                            Text(kind.title).font(.callout)
                        }
                    }
                } header: {
                    Text("Content type (network)")
                } footer: {
                    Text("When a selection is made, only network responses of these types are listed (non-network entries are hidden).")
                }

                let categories = model.availableCategories
                if !categories.isEmpty {
                    Section("Categories") {
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
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { model.resetFilters() }
                        .disabled(!model.isFiltering)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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

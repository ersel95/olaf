#if canImport(UIKit)
import SwiftUI

/// The mocking hub: which endpoints are mocked and with which variant, the global override, and
/// saved scenarios.
///
/// New endpoints arrive via **"Convert to Mock"** in a network entry's detail view. From here you
/// switch variants, send an endpoint back to **Original** (real backend, definitions kept), or flip
/// the whole set at once with a scenario.
struct MockListView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var endpoints: [OlafMockEndpoint] = []
    @State private var templates: [OlafMockTemplate] = []
    @State private var scenarios: [OlafMockScenario] = []
    @State private var globalTemplateID: UUID?
    @State private var isNamingScenario = false
    @State private var scenarioName = ""

    var body: some View {
        CompatNavigationStack {
            List {
                globalSection
                endpointsSection
                scenariosSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Mocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Reset all to Original") {
                            OlafNetwork.resetAllToOriginal()
                            reload()
                        }
                        .disabled(!isAnythingServed)

                        Button("Remove all mocks", role: .destructive) {
                            OlafNetwork.removeAllMocks()
                            reload()
                        }
                        .disabled(endpoints.isEmpty && globalTemplateID == nil)
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: reload)
            .alert("Save scenario", isPresented: $isNamingScenario) {
                TextField("Name", text: $scenarioName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveScenario() }
                    .disabled(scenarioName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Stores which variant each endpoint is on, plus the global override, so you can come back to this exact setup.")
            }
        }
    }

    // MARK: - Sections

    private var globalSection: some View {
        Section {
            Picker("Applies to all", selection: globalSelection) {
                Text("None").tag(UUID?.none)
                ForEach(templates) { template in
                    Text(template.name).tag(UUID?.some(template.id))
                }
            }
            NavigationLink {
                MockTemplatesView()
            } label: {
                Label("Templates", systemImage: "square.on.square")
            }
        } header: {
            Text("Global override")
        } footer: {
            Text("Served to every captured request that has no endpoint of its own — unlike endpoint mocks it respects the capture filters, and endpoints set to Original are left alone.")
        }
    }

    @ViewBuilder
    private var endpointsSection: some View {
        if endpoints.isEmpty {
            Section {
                Text("No mocked endpoints. Add one from a network entry's detail view via \"Convert to Mock\"; matching requests then get that response without hitting the network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Endpoints")
            }
        } else {
            Section {
                ForEach(endpoints) { endpoint in
                    NavigationLink {
                        MockVariantsView(endpointID: endpoint.id)
                    } label: {
                        row(endpoint)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            OlafNetwork.resetEndpoint(id: endpoint.id)
                            reload()
                        } label: {
                            Label("Reset", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.orange)
                        .disabled(endpoint.activeVariantID == nil)
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("Endpoints")
            } footer: {
                Text("If multiple endpoints match, the first one added wins. Swipe right to reset one to Original, left to delete it. Mocks reset on app restart.")
            }
        }
    }

    @ViewBuilder
    private var scenariosSection: some View {
        Section {
            ForEach(scenarios) { scenario in
                Button {
                    OlafNetwork.applyScenario(id: scenario.id)
                    reload()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scenario.name)
                        Text(summary(of: scenario))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .onDelete { offsets in
                for index in offsets {
                    OlafNetwork.removeScenario(id: scenarios[index].id)
                }
                reload()
            }

            Button {
                scenarioName = ""
                isNamingScenario = true
            } label: {
                Label("Save current state…", systemImage: "square.and.arrow.down")
            }
            .disabled(endpoints.isEmpty && globalTemplateID == nil)
        } header: {
            Text("Scenarios")
        } footer: {
            Text("Applying a scenario switches every endpoint at once; endpoints it doesn't name go back to Original.")
        }
    }

    private func row(_ endpoint: OlafMockEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                MethodBadge(method: endpoint.method ?? "ALL")
                Text(endpoint.urlContains)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let variant = endpoint.activeVariant {
                HStack(spacing: 6) {
                    Text(variant.name)
                        .font(.caption2)
                    MockPayloadSummary(payload: variant.payload)
                }
            } else {
                Text("Original · \(endpoint.variants.count) variant\(endpoint.variants.count == 1 ? "" : "s") saved")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Derived state

    /// Reading straight from the registry keeps the picker honest if a template disappears.
    private var globalSelection: Binding<UUID?> {
        Binding(
            get: { globalTemplateID },
            set: { newValue in
                OlafNetwork.globalMockTemplateID = newValue
                reload()
            }
        )
    }

    private var isAnythingServed: Bool {
        globalTemplateID != nil || endpoints.contains { $0.activeVariantID != nil }
    }

    private func summary(of scenario: OlafMockScenario) -> String {
        let count = scenario.selections.count
        var parts = ["\(count) endpoint\(count == 1 ? "" : "s")"]
        if let templateID = scenario.globalTemplateID,
           let template = templates.first(where: { $0.id == templateID }) {
            parts.append("global: \(template.name)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            OlafNetwork.removeEndpoint(id: endpoints[index].id)
        }
        reload()
    }

    private func saveScenario() {
        let name = scenarioName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        OlafNetwork.saveScenario(name: name)
        reload()
    }

    private func reload() {
        endpoints = OlafNetwork.mockEndpoints
        templates = OlafNetwork.mockTemplates
        scenarios = OlafNetwork.mockScenarios
        globalTemplateID = OlafNetwork.globalMockTemplateID
    }
}
#endif

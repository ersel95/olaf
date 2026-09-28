#if canImport(UIKit)
import SwiftUI

/// The saved responses of one endpoint, and which one is being served.
///
/// **Original** is always the first row: picking it sends the endpoint back to the real backend
/// without deleting anything — the variants stay listed, one tap away from being switched on again.
struct MockVariantsView: View {

    let endpointID: UUID

    @State private var endpoint: OlafMockEndpoint?
    @State private var templates: [OlafMockTemplate] = []
    @State private var editing: EditingVariant?

    /// Identifies the variant the editor sheet is open for.
    private struct EditingVariant: Identifiable {
        let endpoint: OlafMockEndpoint
        let variant: OlafMockVariant
        var id: UUID { variant.id }
    }

    var body: some View {
        Group {
            if let endpoint {
                List {
                    servingSection(endpoint)
                    addSection(endpoint)
                }
                .listStyle(.insetGrouped)
                .navigationTitle(endpoint.method.map { "\($0) mock" } ?? "Mock")
            } else {
                EmptyStateView("Endpoint removed", systemImage: "questionmark.circle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(item: $editing, onDismiss: reload) { editing in
            MockEditorView(endpoint: editing.endpoint, variant: editing.variant)
        }
    }

    // MARK: - Sections

    private func servingSection(_ endpoint: OlafMockEndpoint) -> some View {
        Section {
            Button {
                OlafNetwork.resetEndpoint(id: endpointID)
                reload()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Original")
                        Text("Real backend — the global override doesn't apply either")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if endpoint.activeVariantID == nil {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .foregroundStyle(.primary)

            ForEach(endpoint.variants) { variant in
                variantRow(variant, isActive: variant.id == endpoint.activeVariantID)
            }
            .onDelete { offsets in
                for index in offsets {
                    OlafNetwork.removeVariant(id: endpoint.variants[index].id, from: endpointID)
                }
                reload()
            }
        } header: {
            Text(endpoint.urlContains)
                .font(.caption.monospaced())
                .textCase(nil)
        } footer: {
            Text("Tap a variant to serve it. Swipe to delete; deleting the served one falls back to Original.")
        }
    }

    private func variantRow(_ variant: OlafMockVariant, isActive: Bool) -> some View {
        Button {
            OlafNetwork.selectVariant(variant.id, for: endpointID)
            reload()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.name)
                    MockPayloadSummary(payload: variant.payload)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .leading) {
            Button {
                guard let endpoint else { return }
                editing = EditingVariant(endpoint: endpoint, variant: variant)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func addSection(_ endpoint: OlafMockEndpoint) -> some View {
        Section {
            Menu {
                ForEach(templates) { template in
                    Button(template.name) { addVariant(from: template) }
                }
            } label: {
                Label("Add variant from template", systemImage: "plus")
            }
        } footer: {
            Text("Templates are URL-agnostic responses — the built-in error cases plus anything you saved from the mock editor.")
        }
    }

    // MARK: - Actions

    private func addVariant(from template: OlafMockTemplate) {
        OlafNetwork.addVariant(
            OlafMockVariant(name: template.name, payload: template.payload),
            to: endpointID
        )
        reload()
    }

    private func reload() {
        endpoint = OlafNetwork.mockEndpoints.first { $0.id == endpointID }
        templates = OlafNetwork.mockTemplates
    }
}

/// One-line description of a mock response — shared by the variant, template and endpoint rows.
struct MockPayloadSummary: View {

    let payload: OlafMockPayload

    var body: some View {
        HStack(spacing: 8) {
            if let errorCode = payload.transportError {
                Text("Transport error (\(errorCode.rawValue))")
                    .foregroundStyle(.red)
            } else {
                Text("→ \(payload.statusCode)")
                if !payload.body.isEmpty {
                    Text("· \(Formatting.byteCount(payload.body.count))")
                }
            }
            if payload.delaySeconds > 0 {
                Text("· \(String(format: "%.1f", payload.delaySeconds))s delay")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
#endif

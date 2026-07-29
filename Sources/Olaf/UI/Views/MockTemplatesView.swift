#if canImport(UIKit)
import SwiftUI

/// The template library: URL-agnostic responses that can be dropped onto any endpoint as a variant
/// or switched on as the global override. Built-ins ship with Olaf and can't be deleted; the rest
/// come from the mock editor's "Save as template".
struct MockTemplatesView: View {

    @State private var templates: [OlafMockTemplate] = []

    var body: some View {
        List {
            Section {
                ForEach(templates) { template in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(template.name)
                            if template.isBuiltIn {
                                Text("built-in")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        MockPayloadSummary(payload: template.payload)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Apply a template from an endpoint's variant list, or switch one on as the global override in the mock list. Built-in templates can't be deleted.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { templates = OlafNetwork.mockTemplates }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets where !templates[index].isBuiltIn {
            OlafNetwork.removeTemplate(id: templates[index].id)
        }
        templates = OlafNetwork.mockTemplates
    }
}
#endif

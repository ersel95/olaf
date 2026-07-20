#if canImport(UIKit)
import SwiftUI

/// List of active mocks: view, remove individually (by swiping), or remove all at once.
/// New mocks are added via **"Convert to Mock"** in a network entry's detail view.
struct MockListView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var mocks: [OlafMockResponse] = OlafNetwork.activeMocks

    var body: some View {
        NavigationStack {
            Group {
                if mocks.isEmpty {
                    ContentUnavailableView(
                        "No mocks",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Add one from a network entry's detail view via \"Convert to Mock\"; matching requests get that response without hitting the network.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(mocks) { mock in
                                row(mock)
                            }
                            .onDelete(perform: delete)
                        } footer: {
                            Text("If multiple mocks match, the first one added wins. Mocks reset on app restart.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Mocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Remove All", role: .destructive) {
                        OlafNetwork.removeAllMocks()
                        mocks = []
                    }
                    .disabled(mocks.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { mocks = OlafNetwork.activeMocks }
        }
    }

    private func row(_ mock: OlafMockResponse) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                MethodBadge(method: mock.method ?? "ALL")
                Text(mock.urlContains)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                if let errorCode = mock.transportError {
                    Text("Transport error (\(errorCode.rawValue))")
                        .foregroundStyle(.red)
                } else {
                    Text("→ \(mock.statusCode)")
                    if !mock.body.isEmpty {
                        Text("· \(Formatting.byteCount(mock.body.count))")
                    }
                }
                if mock.delaySeconds > 0 {
                    Text("· \(String(format: "%.1f", mock.delaySeconds))s delay")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            OlafNetwork.removeMock(id: mocks[index].id)
        }
        mocks = OlafNetwork.activeMocks
    }
}
#endif

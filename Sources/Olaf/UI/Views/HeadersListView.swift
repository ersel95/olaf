#if canImport(UIKit)
import SwiftUI

/// Full-screen view showing headers as key-value rows. Each row is collapsible
/// (collapsed by default: single-line preview; expanded: full selectable value).
struct HeadersListView: View {
    let title: String
    let headers: [(key: String, value: String)]

    var body: some View {
        List {
            ForEach(headers, id: \.key) { header in
                HeaderRow(key: header.key, value: header.value)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HeaderRow: View {
    let key: String
    let value: String

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(key)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !isExpanded {
                    Text(value)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
#endif

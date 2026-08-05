#if canImport(UIKit)
import SwiftUI

/// Full-screen view showing headers as key-value rows. Each row is collapsible
/// (collapsed by default: single-line preview; expanded: full selectable value).
struct HeadersListView: View {
    let title: String
    let headers: [(key: String, value: String)]

    @State private var didCopy = false

    var body: some View {
        List {
            ForEach(headers, id: \.key) { header in
                HeaderRow(key: header.key, value: header.value, didCopy: $didCopy)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .copyToast($didCopy)
    }
}

private struct HeaderRow: View {
    let key: String
    let value: String
    @Binding var didCopy: Bool

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            HStack(alignment: .top, spacing: 12) {
                Text(value)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Selection works, but dragging a token across several lines is fiddly —
                // one tap copies the whole value.
                Button {
                    olafCopy(value, showing: $didCopy)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy \(key)")
            }
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

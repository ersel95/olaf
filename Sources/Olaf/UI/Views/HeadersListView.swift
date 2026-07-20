#if canImport(UIKit)
import SwiftUI

/// Full-screen view showing headers as key-value rows. Values are selectable.
struct HeadersListView: View {
    let title: String
    let headers: [(key: String, value: String)]

    var body: some View {
        List {
            ForEach(headers, id: \.key) { header in
                VStack(alignment: .leading, spacing: 2) {
                    Text(header.key)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(header.value)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

#if canImport(UIKit)
import SwiftUI

/// Tam ekran, seçilebilir + aranabilir + paylaşılabilir metin görüntüleyici (gövde / cURL).
/// JSON ise pretty-print uygulanır. Arama: eşleşen satırlar süzülür.
struct TextViewerView: View {
    let title: String
    let rawText: String

    @State private var query = ""
    @State private var isSharePresented = false

    private var display: String {
        Formatting.isJSON(rawText) ? Formatting.prettyJSON(rawText) : rawText
    }

    private var filtered: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return display }
        let lines = display
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.range(of: q, options: .caseInsensitive) != nil }
        return lines.isEmpty ? "(eşleşme yok)" : lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(filtered)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Bul")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { UIPasteboard.general.string = display } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Kopyala")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isSharePresented = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Paylaş")
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: [display])
        }
    }
}
#endif

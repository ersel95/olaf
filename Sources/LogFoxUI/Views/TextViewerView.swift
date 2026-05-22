#if canImport(UIKit)
import SwiftUI

/// Tam ekran, seçilebilir + aranabilir + paylaşılabilir metin görüntüleyici (gövde / cURL).
/// JSON ise pretty-print uygulanır. Arama: eşleşen satırlar süzülür.
struct TextViewerView: View {
    let title: String
    let rawText: String

    @State private var query = ""
    @State private var didCopy = false
    /// Varsayılan: satır kaydır (ekrana sığar). Kapatınca ham (yatay kaydırmalı) gösterim.
    @State private var wrapLines = true

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
        Group {
            if wrapLines {
                ScrollView(.vertical) {
                    Text(filtered)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(filtered)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Bul")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { wrapLines.toggle() } label: {
                    Image(systemName: wrapLines ? "text.alignleft" : "arrow.left.and.right")
                }
                .accessibilityLabel(wrapLines ? "Satır kaydırmayı kapat" : "Satır kaydır")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { logFoxCopy(display, showing: $didCopy) } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .accessibilityLabel("Kopyala")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { presentShareSheet([display]) } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Paylaş")
            }
        }
        .copyToast($didCopy)
    }
}
#endif

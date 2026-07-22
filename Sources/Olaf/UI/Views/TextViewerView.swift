#if canImport(UIKit)
import SwiftUI

/// Full-screen, selectable + searchable + shareable text viewer (body / cURL).
/// Pretty-printed if JSON. Search: matching lines are filtered.
struct TextViewerView: View {
    let title: String
    let rawText: String

    @State private var query = ""
    @State private var didCopy = false
    /// Default: wrap lines (fits the screen). When off, raw (horizontally scrollable) display.
    @State private var wrapLines = true

    private var display: String {
        Formatting.isJSON(rawText) ? Formatting.prettyJSON(rawText) : rawText
    }

    /// Highlighted if JSON, plain text otherwise. Keyed to `display`, not `filtered`:
    /// a search result may start mid-document (e.g. `"key" : {`) and still deserves colors.
    private var bodyText: Text {
        Formatting.looksLikeJSON(display)
            ? Text(JSONHighlighter.attributed(filtered))
            : Text(filtered)
    }

    private var filtered: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return display }
        if Formatting.looksLikeJSON(display) {
            return Formatting.searchKeepingJSONBlocks(display, query: q) ?? "(no matches)"
        }
        let lines = display
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.range(of: q, options: .caseInsensitive) != nil }
        return lines.isEmpty ? "(no matches)" : lines.joined(separator: "\n")
    }

    var body: some View {
        Group {
            if wrapLines {
                ScrollView(.vertical) {
                    bodyText
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                ScrollView([.vertical, .horizontal]) {
                    bodyText
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { wrapLines.toggle() } label: {
                    Image(systemName: wrapLines ? "text.alignleft" : "arrow.left.and.right")
                }
                .accessibilityLabel(wrapLines ? "Turn off line wrap" : "Wrap lines")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { olafCopy(display, showing: $didCopy) } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .accessibilityLabel("Copy")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { presentShareSheet([display]) } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
        }
        .copyToast($didCopy)
    }
}
#endif

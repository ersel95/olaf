#if canImport(UIKit)
import SwiftUI

/// JSON metnini regex tabanlı renklendirip `AttributedString` döndürür (key/string/sayı/literal).
/// Katı parse yapmaz → redaksiyon/truncation ile bozulmuş JSON'u da renklendirir.
enum JSONHighlighter {

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = .primary

        // Sıra önemli: önce tüm string'ler, sonra key'ler (string'in üstüne yazar).
        colorize(#""(?:\\.|[^"\\])*""#, .green, in: &result, source: text)            // string değerler
        colorize(#""(?:\\.|[^"\\])*"(?=\s*:)"#, .purple, in: &result, source: text)   // key'ler
        colorize(#"(?<![\w"])-?\d+(?:\.\d+)?(?![\w"])"#, .teal, in: &result, source: text) // sayılar
        colorize(#"\b(?:true|false|null)\b"#, .orange, in: &result, source: text)      // literal

        return result
    }

    private static func colorize(_ pattern: String, _ color: Color, in attr: inout AttributedString, source: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let full = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: full) {
            guard let stringRange = Range(match.range, in: source),
                  let low = AttributedString.Index(stringRange.lowerBound, within: attr),
                  let high = AttributedString.Index(stringRange.upperBound, within: attr) else { continue }
            attr[low..<high].foregroundColor = color
        }
    }
}
#endif

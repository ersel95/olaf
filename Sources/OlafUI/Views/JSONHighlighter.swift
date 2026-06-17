#if canImport(UIKit)
import SwiftUI

/// JSON metnini regex tabanlı renklendirip `AttributedString` döndürür (key/string/sayı/literal).
/// Katı parse yapmaz → truncation ile bozulmuş JSON'u da renklendirir.
enum JSONHighlighter {

    /// Pattern'ler statik literal → regex'ler bir kez derlenir (her detay render'ında yeniden
    /// derleme yok). `NSRegularExpression` thread-safe. `try!` güvenli: derleme-zamanı sabitleri.
    private enum Regexes {
        static let string = try! NSRegularExpression(pattern: #""(?:\\.|[^"\\])*""#)
        static let key = try! NSRegularExpression(pattern: #""(?:\\.|[^"\\])*"(?=\s*:)"#)
        static let number = try! NSRegularExpression(pattern: #"(?<![\w"])-?\d+(?:\.\d+)?(?![\w"])"#)
        static let literal = try! NSRegularExpression(pattern: #"\b(?:true|false|null)\b"#)
    }

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = .primary

        // Sıra önemli: önce tüm string'ler, sonra key'ler (string'in üstüne yazar).
        colorize(Regexes.string, .green, in: &result, source: text)   // string değerler
        colorize(Regexes.key, .purple, in: &result, source: text)     // key'ler
        colorize(Regexes.number, .teal, in: &result, source: text)    // sayılar
        colorize(Regexes.literal, .orange, in: &result, source: text) // literal

        return result
    }

    private static func colorize(_ regex: NSRegularExpression, _ color: Color, in attr: inout AttributedString, source: String) {
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

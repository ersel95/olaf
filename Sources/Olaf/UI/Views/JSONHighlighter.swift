#if canImport(UIKit)
import SwiftUI

/// Highlights JSON text via regex and returns an `AttributedString` (key/string/number/literal).
/// Does not strict-parse → also highlights JSON broken by truncation.
enum JSONHighlighter {

    /// Patterns are static literals → regexes are compiled once (no recompilation on every
    /// detail render). `NSRegularExpression` is thread-safe. `try!` is safe: compile-time constants.
    private enum Regexes {
        static let string = try! NSRegularExpression(pattern: #""(?:\\.|[^"\\])*""#)
        static let key = try! NSRegularExpression(pattern: #""(?:\\.|[^"\\])*"(?=\s*:)"#)
        static let number = try! NSRegularExpression(pattern: #"(?<![\w"])-?\d+(?:\.\d+)?(?![\w"])"#)
        static let literal = try! NSRegularExpression(pattern: #"\b(?:true|false|null)\b"#)
    }

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = .primary

        // Order matters: color all strings first, then keys (overwrites over the string color).
        colorize(Regexes.string, .green, in: &result, source: text)   // string values
        colorize(Regexes.key, .purple, in: &result, source: text)     // keys
        colorize(Regexes.number, .teal, in: &result, source: text)    // numbers
        colorize(Regexes.literal, .orange, in: &result, source: text) // literals

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

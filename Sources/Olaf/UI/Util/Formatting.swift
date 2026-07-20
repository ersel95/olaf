import Foundation

/// Display helpers: JSON pretty-printing and byte-size formatting.
enum Formatting {

    /// Returns the text indented if it is valid JSON; otherwise returns it unchanged.
    static func prettyJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
              ),
              let string = String(data: pretty, encoding: .utf8) else {
            return text
        }
        return string
    }

    /// Is the content JSON? (monospace + pretty are applied in the detail view.)
    static func isJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// Does it LOOK LIKE JSON? (truncation may have broken otherwise-valid JSON; for
    /// highlighting purposes, checking that it starts with `{`/`[` is enough — no strict parse.)
    static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    static func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

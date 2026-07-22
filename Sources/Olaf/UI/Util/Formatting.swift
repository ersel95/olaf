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

    /// Line-based search filter that keeps JSON blocks whole: when a matching line opens an
    /// object/array continuing on later lines (e.g. `"key" : {`), the entire block down to its
    /// matching close is included — a lone `"key" : {` line is meaningless to the reader.
    /// Disjoint blocks are separated with `⋯`. Returns nil when nothing matches.
    static func searchKeepingJSONBlocks(_ text: String, query: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var depthAtStart = [Int](repeating: 0, count: lines.count)
        var depthAtEnd = [Int](repeating: 0, count: lines.count)
        var depth = 0
        for (i, line) in lines.enumerated() {
            depthAtStart[i] = depth
            depth += bracketDelta(line)
            depthAtEnd[i] = depth
        }

        var included = [Bool](repeating: false, count: lines.count)
        var anyMatch = false
        for i in lines.indices where lines[i].range(of: query, options: .caseInsensitive) != nil {
            anyMatch = true
            included[i] = true
            // The match opens a block that doesn't close on the same line → include it whole.
            guard depthAtEnd[i] > depthAtStart[i] else { continue }
            var j = i + 1
            while j < lines.count {
                included[j] = true
                if depthAtEnd[j] <= depthAtStart[i] { break }
                j += 1
            }
        }
        guard anyMatch else { return nil }

        var out: [String] = []
        var lastIncluded = -1
        for i in lines.indices where included[i] {
            if lastIncluded >= 0, i > lastIncluded + 1 { out.append("⋯") }
            out.append(String(lines[i]))
            lastIncluded = i
        }
        return out.joined(separator: "\n")
    }

    /// Net `{`/`[` minus `}`/`]` on the line, ignoring brackets inside string literals.
    private static func bracketDelta(_ line: Substring) -> Int {
        var delta = 0
        var inString = false
        var escaped = false
        for ch in line {
            if escaped { escaped = false; continue }
            switch ch {
            case "\\" where inString: escaped = true
            case "\"": inString.toggle()
            case "{", "[": if !inString { delta += 1 }
            case "}", "]": if !inString { delta -= 1 }
            default: break
            }
        }
        return delta
    }
}

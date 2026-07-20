import Foundation

/// Converts each entry into single-line JSON (NDJSON). For export and future remote sinks.
public struct JSONLogFormatter: LogFormatter {

    private let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        self.encoder = encoder
    }

    public func string(from entry: LogEntry) -> String {
        guard let data = try? encoder.encode(entry),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"encode_failed\"}"
        }
        return json
    }
}

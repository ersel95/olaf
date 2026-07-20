import Foundation

/// Strategy for converting a `LogEntry` into text. The viewer may use the plain-text formatter,
/// while export may use the JSON formatter.
public protocol LogFormatter: Sendable {
    func string(from entry: LogEntry) -> String
}

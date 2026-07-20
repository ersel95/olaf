import Foundation

/// Human-readable single-line format:
/// `HH:mm:ss.SSS [LEVEL] [category] message {k=v} (File.swift:line)`
public struct PlainTextFormatter: LogFormatter {

    public var includesMetadata: Bool
    public var includesSource: Bool

    public init(includesMetadata: Bool = true, includesSource: Bool = true) {
        self.includesMetadata = includesMetadata
        self.includesSource = includesSource
    }

    public func string(from entry: LogEntry) -> String {
        var line = "\(Self.timeFormatter.string(from: entry.date)) "
        line += "[\(entry.level.name)] "
        line += "[\(entry.category.rawValue)] "
        line += entry.message

        if includesMetadata, !entry.metadata.isEmpty {
            let pairs = entry.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            line += " {\(pairs)}"
        }

        if includesSource {
            line += " (\(entry.fileName):\(entry.line))"
        }

        return line
    }

    /// Fixed, locale-independent time format (for consistent sorting and readability).
    public static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

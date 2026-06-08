import Foundation

/// İnsan-okur tek satır biçim:
/// `HH:mm:ss.SSS [LEVEL] [category] mesaj {k=v} (Dosya.swift:line)`
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

    /// Sabit, locale-bağımsız zaman biçimi (sıralama ve okuma tutarlılığı için).
    public static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

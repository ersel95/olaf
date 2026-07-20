import Foundation

/// A single log entry. `message` and `metadata` are stored **raw**, exactly as they came from
/// the call site (no masking/filtering is applied — all data is kept as-is).
public struct LogEntry: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let date: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    public let metadata: [String: String]
    public let file: String
    public let line: Int
    public let function: String
    public let thread: String
    /// The app session this entry belongs to (each `Olaf.start()` generates a new identifier).
    /// Used to group entries by session in the history view.
    public let sessionID: String

    public init(
        id: UUID = UUID(),
        date: Date,
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: String],
        file: String,
        line: Int,
        function: String,
        thread: String,
        sessionID: String = ""
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
        self.file = file
        self.line = line
        self.function = function
        self.thread = thread
        self.sessionID = sessionID
    }

    // Lenient decoding: allows old (pre-0.9) NDJSON entries without a `sessionID` to be read too.
    private enum CodingKeys: String, CodingKey {
        case id, date, level, category, message, metadata, file, line, function, thread, sessionID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        level = try c.decode(LogLevel.self, forKey: .level)
        category = try c.decode(LogCategory.self, forKey: .category)
        message = try c.decode(String.self, forKey: .message)
        metadata = try c.decode([String: String].self, forKey: .metadata)
        file = try c.decode(String.self, forKey: .file)
        line = try c.decode(Int.self, forKey: .line)
        function = try c.decode(String.self, forKey: .function)
        thread = try c.decode(String.self, forKey: .thread)
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
    }

    /// `#fileID` returns "Module/Sub/File.swift"; used to show only the file name in the viewer.
    public var fileName: String {
        (file as NSString).lastPathComponent
    }
}

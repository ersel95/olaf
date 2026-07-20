import Foundation

/// The return value of `Olaf.loadPersistedPage(before:minimumEntries:)`: a page of history.
public struct PersistedLogPage: Sendable {
    /// The page's entries — **oldest to newest** (the caller prepends them to previous pages).
    public let entries: [LogEntry]

    /// The **opaque** cursor to pass to the next call for older entries.
    /// `nil` → the end of history has been reached.
    public let nextCursor: String?

    public init(entries: [LogEntry], nextCursor: String?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }
}

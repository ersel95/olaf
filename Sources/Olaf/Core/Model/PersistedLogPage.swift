import Foundation

/// `Olaf.loadPersistedPage(before:minimumEntries:)`'in dönüşü: geçmişin bir sayfası.
public struct PersistedLogPage: Sendable {
    /// Sayfanın kayıtları — **eskiden yeniye** (çağıran, önceki sayfaların BAŞINA ekler).
    public let entries: [LogEntry]

    /// Daha eski kayıtlar için bir sonraki çağrıya verilecek **opak** imleç.
    /// `nil` → geçmişin sonuna gelindi.
    public let nextCursor: String?

    public init(entries: [LogEntry], nextCursor: String?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }
}

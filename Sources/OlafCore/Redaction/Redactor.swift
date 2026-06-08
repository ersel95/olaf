import Foundation

/// Yazma anında hassas veriyi maskeleyen katman. Maskeleme depolamadan **önce**
/// uygulanır; ham PII ring buffer'a, diske veya konsola asla yazılmaz.
public protocol Redactor: Sendable {
    /// Serbest metin mesajı içindeki hassas örüntüleri maskeler.
    func redact(_ text: String) -> String

    /// Metadata sözlüğünü; hem değerlerdeki örüntüleri hem de hassas anahtarları maskeler.
    func redact(metadata: [String: String]) -> [String: String]
}

public extension Redactor {
    /// Tek bir `LogEntry`'yi redakte edilmiş kopyası ile döndürür (message + metadata).
    /// Diğer alanlar (tarih/seviye/kategori/dosya/satır…) hassas veri taşımaz, korunur.
    func redact(entry: LogEntry) -> LogEntry {
        LogEntry(
            id: entry.id,
            date: entry.date,
            level: entry.level,
            category: entry.category,
            message: redact(entry.message),
            metadata: redact(metadata: entry.metadata),
            file: entry.file,
            line: entry.line,
            function: entry.function,
            thread: entry.thread,
            sessionID: entry.sessionID
        )
    }

    /// Bir `LogEntry` dizisini redakte eder. Upload öncesi zorunlu redaksiyon için kullanılır.
    func redact(entries: [LogEntry]) -> [LogEntry] {
        entries.map { redact(entry: $0) }
    }
}

/// Hiçbir şey yapmayan redaksiyon — yalnız test/teşhis için. Üretimde kullanmayın.
public struct NoopRedactor: Redactor {
    public init() {}
    public func redact(_ text: String) -> String { text }
    public func redact(metadata: [String: String]) -> [String: String] { metadata }
}

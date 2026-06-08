import Foundation

/// Yazma anında hassas veriyi maskeleyen katman. Maskeleme depolamadan **önce**
/// uygulanır; ham PII ring buffer'a, diske veya konsola asla yazılmaz.
public protocol Redactor: Sendable {
    /// Serbest metin mesajı içindeki hassas örüntüleri maskeler.
    func redact(_ text: String) -> String

    /// Metadata sözlüğünü; hem değerlerdeki örüntüleri hem de hassas anahtarları maskeler.
    func redact(metadata: [String: String]) -> [String: String]
}

/// Hiçbir şey yapmayan redaksiyon — yalnız test/teşhis için. Üretimde kullanmayın.
public struct NoopRedactor: Redactor {
    public init() {}
    public func redact(_ text: String) -> String { text }
    public func redact(metadata: [String: String]) -> [String: String] { metadata }
}

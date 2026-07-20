import Foundation

/// Yanıtın `Content-Type`'ına göre kaba içerik sınıfı — viewer'daki "İçerik türü" filtresi
/// (Netfox tarzı: JSON/XML/HTML/Görsel/Metin/Diğer).
public enum NetworkContentKind: String, CaseIterable, Hashable, Sendable {
    case json, xml, html, image, text, other

    var title: String {
        switch self {
        case .json: return "JSON"
        case .xml: return "XML"
        case .html: return "HTML"
        case .image: return "Görsel"
        case .text: return "Metin"
        case .other: return "Diğer"
        }
    }

    /// Bir kaydın içerik sınıfı; network kaydı değilse `nil`.
    /// Yanıt header'ı yakalanmamışsa (veya Content-Type yoksa) `.other` sayılır.
    static func of(_ entry: LogEntry) -> NetworkContentKind? {
        guard entry.category == .network else { return nil }
        let contentType = entry.metadata
            .first { $0.key.lowercased() == "resph.content-type" }?
            .value.lowercased()
        guard let contentType else { return .other }
        if contentType.contains("json") { return .json }
        if contentType.contains("image/") { return .image }
        if contentType.contains("html") { return .html }
        if contentType.contains("xml") { return .xml }
        if contentType.contains("text/") { return .text }
        return .other
    }
}

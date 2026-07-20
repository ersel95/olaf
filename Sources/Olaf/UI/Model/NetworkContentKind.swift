import Foundation

/// Coarse content class based on the response's `Content-Type` — used by the viewer's "Content type"
/// filter (Netfox-style: JSON/XML/HTML/Image/Text/Other).
public enum NetworkContentKind: String, CaseIterable, Hashable, Sendable {
    case json, xml, html, image, text, other

    var title: String {
        switch self {
        case .json: return "JSON"
        case .xml: return "XML"
        case .html: return "HTML"
        case .image: return "Image"
        case .text: return "Text"
        case .other: return "Other"
        }
    }

    /// A record's content class; `nil` if it's not a network record.
    /// Counted as `.other` if the response header wasn't captured (or there's no Content-Type).
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

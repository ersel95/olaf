import Foundation

/// Bir network olayının ham verisi (maskeleme/filtreleme yapılmaz, olduğu gibi loglanır).
struct NetworkLogEvent {
    var method: String
    var url: String
    var statusCode: Int?
    var durationMs: Int
    var requestBytes: Int
    var responseBytes: Int
    var error: String?
    var requestBody: String?
    var responseBody: String?
    var requestHeaders: [String: String]?
    var responseHeaders: [String: String]?
    /// İstek tamamlanmadan iptal edildi (`NSURLErrorCancelled` — örn. ekran kapandı, prefetch
    /// vazgeçildi). Gerçek bir hata değildir; `.info` seviyesinde loglanır, `error` alanı boş kalır.
    var cancelled: Bool = false
}

/// Network olayını seviye + mesaj + metadata'ya dönüştürür. Saf fonksiyonlar → test edilebilir.
enum NetworkLogComposer {

    static func level(statusCode: Int?, error: String?, cancelled: Bool = false) -> LogLevel {
        if cancelled { return .info }
        if error != nil { return .error }
        guard let status = statusCode else { return .info }
        switch status {
        case 500...: return .error
        case 400..<500: return .warning
        default: return .info
        }
    }

    static func message(for event: NetworkLogEvent) -> String {
        var parts = ["\(event.method)", event.url]
        if let status = event.statusCode { parts.append("→ \(status)") }
        if event.cancelled { parts.append("→ iptal") }
        if event.error != nil { parts.append("→ ✗") }
        parts.append("(\(event.durationMs)ms)")
        return parts.joined(separator: " ")
    }

    static func metadata(for event: NetworkLogEvent) -> [String: String] {
        var metadata: [String: String] = [
            "method": event.method,
            "url": event.url,
            "durationMs": String(event.durationMs),
            "reqBytes": String(event.requestBytes),
            "respBytes": String(event.responseBytes)
        ]
        if let status = event.statusCode { metadata["status"] = String(status) }
        if let error = event.error { metadata["error"] = error }
        if event.cancelled { metadata["cancelled"] = "true" }
        // Gövdeler ayrı `requestBody`/`responseBody` anahtarlarıyla ham olarak saklanır.
        if let body = event.requestBody { metadata["requestBody"] = body }
        if let body = event.responseBody { metadata["responseBody"] = body }
        // Header'lar ayrı anahtarlarla ham olarak saklanır.
        for (key, value) in event.requestHeaders ?? [:] { metadata["reqH.\(key)"] = value }
        for (key, value) in event.responseHeaders ?? [:] { metadata["respH.\(key)"] = value }
        return metadata
    }
}

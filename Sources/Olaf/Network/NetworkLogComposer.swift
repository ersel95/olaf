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
    /// `URLSessionTaskMetrics`'ten çıkarılan zamanlama kırılımı (toplanamadıysa `nil`).
    var timing: NetworkTimingMetrics?
    /// `image/*` yanıt gövdesi (base64) — yalnız `maxImageBodyBytes` sınırının altındaki
    /// görsellerde dolar; viewer detayında önizleme olarak gösterilir.
    var responseImageBase64: String?
}

/// Bir isteğin faz-faz zamanlama kırılımı ("API mi yavaş, ağ mı?" sorusunun cevabı).
/// Yeniden kullanılan bağlantılarda DNS/bağlantı/TLS fazları doğal olarak boş gelir.
struct NetworkTimingMetrics: Sendable {
    var dnsMs: Int?
    var connectMs: Int?
    var tlsMs: Int?
    /// İstek gönderiminin başlangıcı → yanıtın ilk byte'ı (time to first byte).
    var ttfbMs: Int?
    /// Uygulanan protokol (örn. "h2", "http/1.1", "h3").
    var protocolName: String?
    /// Havuzdaki mevcut bağlantı yeniden kullanıldı mı (yeni handshake yok)?
    var reusedConnection: Bool?
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
        if let image = event.responseImageBase64 { metadata["responseImageBase64"] = image }
        // Header'lar ayrı anahtarlarla ham olarak saklanır.
        for (key, value) in event.requestHeaders ?? [:] { metadata["reqH.\(key)"] = value }
        for (key, value) in event.responseHeaders ?? [:] { metadata["respH.\(key)"] = value }
        // Zamanlama kırılımı `t.` önekiyle saklanır (viewer "Zamanlama" bölümü bunları okur).
        if let timing = event.timing {
            if let v = timing.dnsMs { metadata["t.dnsMs"] = String(v) }
            if let v = timing.connectMs { metadata["t.connectMs"] = String(v) }
            if let v = timing.tlsMs { metadata["t.tlsMs"] = String(v) }
            if let v = timing.ttfbMs { metadata["t.ttfbMs"] = String(v) }
            if let v = timing.protocolName { metadata["t.protocol"] = v }
            if let v = timing.reusedConnection { metadata["t.reused"] = v ? "true" : "false" }
        }
        return metadata
    }
}

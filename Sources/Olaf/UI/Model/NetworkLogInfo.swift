import Foundation

/// `.network` kategorili bir `LogEntry`'nin metadata'sını yapısal network bilgisine ayrıştırır.
/// (Metadata anahtarları `OlafNetwork.NetworkLogComposer` ile hizalıdır.)
struct NetworkLogInfo {
    let method: String?
    let url: String?
    let statusCode: Int?
    let durationMs: Int?
    let requestBytes: Int?
    let responseBytes: Int?
    let error: String?
    /// İstek tamamlanmadan iptal edildi (hata değil; `.info` seviyesinde loglanır).
    let cancelled: Bool
    /// Yanıt mock'tan üretildi (ağa çıkılmadı).
    let mocked: Bool
    let requestBody: String?
    let responseBody: String?
    /// `image/*` yanıt gövdesi (sınır altındaysa yakalanır) — detayda önizleme için.
    let responseImageData: Data?
    let requestHeaders: [(key: String, value: String)]
    let responseHeaders: [(key: String, value: String)]

    // Zamanlama kırılımı (`t.` öneki — NetworkLogComposer ile hizalı; toplanamadıysa nil).
    let dnsMs: Int?
    let connectMs: Int?
    let tlsMs: Int?
    let ttfbMs: Int?
    let protocolName: String?
    let reusedConnection: Bool?

    /// Detayda "Zamanlama" bölümü gösterilecek mi?
    var hasTimings: Bool {
        dnsMs != nil || connectMs != nil || tlsMs != nil || ttfbMs != nil
            || protocolName != nil || reusedConnection != nil
    }

    init?(entry: LogEntry) {
        guard entry.category == .network else { return nil }
        let m = entry.metadata
        method = m["method"]
        url = m["url"]
        statusCode = m["status"].flatMap(Int.init)
        durationMs = m["durationMs"].flatMap(Int.init)
        requestBytes = m["reqBytes"].flatMap(Int.init)
        responseBytes = m["respBytes"].flatMap(Int.init)
        error = m["error"]
        cancelled = m["cancelled"] == "true"
        mocked = m["mocked"] == "true"
        requestBody = m["requestBody"]
        responseBody = m["responseBody"]
        responseImageData = m["responseImageBase64"].flatMap { Data(base64Encoded: $0) }
        requestHeaders = m
            .filter { $0.key.hasPrefix("reqH.") }
            .map { (String($0.key.dropFirst(5)), $0.value) }
            .sorted { $0.0 < $1.0 }
        responseHeaders = m
            .filter { $0.key.hasPrefix("respH.") }
            .map { (String($0.key.dropFirst(6)), $0.value) }
            .sorted { $0.0 < $1.0 }
        dnsMs = m["t.dnsMs"].flatMap(Int.init)
        connectMs = m["t.connectMs"].flatMap(Int.init)
        tlsMs = m["t.tlsMs"].flatMap(Int.init)
        ttfbMs = m["t.ttfbMs"].flatMap(Int.init)
        protocolName = m["t.protocol"]
        reusedConnection = m["t.reused"].map { $0 == "true" }
    }

    /// URL'in path (+ query) kısmı; satırda kısa gösterim için.
    var path: String {
        guard let url, let comps = URLComponents(string: url) else { return url ?? "-" }
        var p = comps.path.isEmpty ? "/" : comps.path
        if let q = comps.query, !q.isEmpty { p += "?\(q)" }
        return p
    }

    /// URL host'u.
    var host: String {
        guard let url, let comps = URLComponents(string: url) else { return "" }
        return comps.host ?? ""
    }

    /// Mock editörünün önerdiği eşleşme kalıbı: host + path (query'siz) — aynı endpoint'in
    /// tüm çağrılarını yakalayacak kadar genel, başka endpoint'lere taşmayacak kadar özgül.
    var suggestedMockPattern: String {
        guard let url, let comps = URLComponents(string: url) else { return url ?? "" }
        return (comps.host ?? "") + (comps.path.isEmpty ? "/" : comps.path)
    }

    var isFailure: Bool {
        if error != nil { return true }
        if let code = statusCode { return code >= 400 }
        return false
    }
}

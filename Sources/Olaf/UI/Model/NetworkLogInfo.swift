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
    let requestBody: String?
    let responseBody: String?
    let requestHeaders: [(key: String, value: String)]
    let responseHeaders: [(key: String, value: String)]

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
        requestBody = m["requestBody"]
        responseBody = m["responseBody"]
        requestHeaders = m
            .filter { $0.key.hasPrefix("reqH.") }
            .map { (String($0.key.dropFirst(5)), $0.value) }
            .sorted { $0.0 < $1.0 }
        responseHeaders = m
            .filter { $0.key.hasPrefix("respH.") }
            .map { (String($0.key.dropFirst(6)), $0.value) }
            .sorted { $0.0 < $1.0 }
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

    var isFailure: Bool {
        if error != nil { return true }
        if let code = statusCode { return code >= 400 }
        return false
    }
}

import Foundation

/// Görünen network kayıtlarını **HAR 1.2** (HTTP Archive) belgesine dönüştürür.
/// HAR; Charles, Proxyman, Chrome DevTools gibi araçlarca doğrudan açılır.
///
/// Kaynak, yakalama anındaki metadata'dır; birebir ölçülemeyen HAR alanları için spec'in
/// "bilinmiyor" değeri (`-1`) kullanılır. Gövdeler yakalandığı hâliyle yazılır (gerekirse
/// kesilmiş / pretty-print edilmiş). İçerik **ham**dır — paylaşmadan önce gözden geçirin.
enum HARExporter {

    /// Verilen kayıtlardan (network olmayanlar atlanır) HAR JSON metni üretir.
    /// Hiç network kaydı yoksa da geçerli (boş `entries`) bir belge döner.
    static func harDocument(from entries: [LogEntry]) -> String? {
        let harEntries = entries.compactMap { entry -> [String: Any]? in
            guard let info = NetworkLogInfo(entry: entry) else { return nil }
            return harEntry(info: info, date: entry.date)
        }
        let document: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "Olaf", "version": "-"],
                "entries": harEntries
            ]
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Entry

    private static func harEntry(info: NetworkLogInfo, date: Date) -> [String: Any] {
        let total = info.durationMs ?? 0
        // HAR sözleşmesi: `connect`, `ssl`'i kapsar → bilinen fazlar dns+connect+wait.
        let known = (info.dnsMs ?? 0) + (info.connectMs ?? 0) + (info.ttfbMs ?? 0)
        let receive = max(0, total - known)

        var request: [String: Any] = [
            "method": info.method ?? "GET",
            "url": info.url ?? "",
            "httpVersion": httpVersion(info.protocolName),
            "cookies": [] as [Any],
            "headers": harHeaders(info.requestHeaders),
            "queryString": queryString(of: info.url),
            "headersSize": -1,
            "bodySize": info.requestBytes ?? -1
        ]
        if let body = info.requestBody, !body.isEmpty {
            request["postData"] = [
                "mimeType": headerValue(info.requestHeaders, "Content-Type") ?? "application/octet-stream",
                "text": body
            ]
        }

        let response: [String: Any] = [
            "status": info.statusCode ?? 0,
            "statusText": info.statusCode.map { HTTPURLResponse.localizedString(forStatusCode: $0) }
                ?? (info.error ?? (info.cancelled ? "cancelled" : "")),
            "httpVersion": httpVersion(info.protocolName),
            "cookies": [] as [Any],
            "headers": harHeaders(info.responseHeaders),
            "content": [
                "size": info.responseBytes ?? -1,
                "mimeType": headerValue(info.responseHeaders, "Content-Type") ?? "application/octet-stream",
                "text": info.responseBody ?? ""
            ],
            "redirectURL": "",
            "headersSize": -1,
            "bodySize": info.responseBytes ?? -1
        ]

        return [
            "startedDateTime": Self.timestampFormatter.string(from: date),
            "time": total,
            "request": request,
            "response": response,
            "cache": [:] as [String: Any],
            "timings": [
                "blocked": -1,
                "dns": info.dnsMs ?? -1,
                "connect": info.connectMs ?? -1,
                "send": 0,
                "wait": info.ttfbMs ?? -1,
                "receive": receive,
                "ssl": info.tlsMs ?? -1
            ]
        ]
    }

    // MARK: - Yardımcılar

    private static func harHeaders(_ headers: [(key: String, value: String)]) -> [[String: String]] {
        headers.map { ["name": $0.key, "value": $0.value] }
    }

    private static func headerValue(_ headers: [(key: String, value: String)], _ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func queryString(of url: String?) -> [[String: String]] {
        guard let url, let items = URLComponents(string: url)?.queryItems else { return [] }
        return items.map { ["name": $0.name, "value": $0.value ?? ""] }
    }

    /// ALPN adını HAR'ın beklediği gösterime çevirir.
    private static func httpVersion(_ protocolName: String?) -> String {
        switch protocolName?.lowercased() {
        case "h2": return "HTTP/2"
        case "h3": return "HTTP/3"
        case let .some(name) where !name.isEmpty: return name
        default: return "HTTP/1.1"
        }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

import Foundation

/// Converts the visible network entries into a **HAR 1.2** (HTTP Archive) document.
/// HAR opens directly in tools like Charles, Proxyman, and Chrome DevTools.
///
/// The source is the metadata captured at capture time; for HAR fields that can't be measured
/// exactly, the spec's "unknown" value (`-1`) is used. Bodies are written as captured (possibly
/// truncated / pretty-printed). Content is **raw** — review before sharing.
enum HARExporter {

    /// Produces HAR JSON text from the given entries (non-network ones are skipped).
    /// Also returns a valid (empty `entries`) document when there are no network entries at all.
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
        // HAR contract: `connect` encompasses `ssl` → known phases are dns+connect+wait.
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

    // MARK: - Helpers

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

    /// Converts the ALPN name into the representation HAR expects.
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

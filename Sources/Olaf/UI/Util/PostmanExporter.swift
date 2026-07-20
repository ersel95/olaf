import Foundation

/// Converts the visible network entries into a **Postman Collection v2.1** document — can be
/// brought directly into Postman via "Import" and the requests re-run.
///
/// The same `method + URL` pair is added once (first seen wins) → repeated calls don't bloat the
/// collection. Header/body values are **raw** (including `Authorization`) — review before sharing.
enum PostmanExporter {

    static func collection(from entries: [LogEntry], name: String = "Olaf Export") -> String? {
        var seen = Set<String>()
        var items: [[String: Any]] = []

        for entry in entries {
            guard let info = NetworkLogInfo(entry: entry), let url = info.url else { continue }
            let method = (info.method ?? "GET").uppercased()
            let dedupeKey = "\(method) \(url)"
            guard seen.insert(dedupeKey).inserted else { continue }
            items.append(item(info: info, method: method, url: url))
        }

        let document: [String: Any] = [
            "info": [
                "name": name,
                "_postman_id": UUID().uuidString.lowercased(),
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": items
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Item

    private static func item(info: NetworkLogInfo, method: String, url: String) -> [String: Any] {
        var request: [String: Any] = [
            "method": method,
            "header": info.requestHeaders.map { ["key": $0.key, "value": $0.value] },
            "url": urlObject(url)
        ]
        if let body = info.requestBody, !body.isEmpty {
            let contentType = info.requestHeaders
                .first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? ""
            var bodyObject: [String: Any] = ["mode": "raw", "raw": body]
            if contentType.lowercased().contains("json") || Formatting.looksLikeJSON(body) {
                bodyObject["options"] = ["raw": ["language": "json"]]
            }
            request["body"] = bodyObject
        }

        return [
            "name": "\(method) \(info.path)",
            "request": request
        ]
    }

    /// Postman's structured URL object (`raw` + parts).
    private static func urlObject(_ url: String) -> [String: Any] {
        guard let components = URLComponents(string: url) else { return ["raw": url] }
        var object: [String: Any] = ["raw": url]
        if let scheme = components.scheme { object["protocol"] = scheme }
        if let host = components.host { object["host"] = host.split(separator: ".").map(String.init) }
        if let port = components.port { object["port"] = String(port) }
        let path = components.path.split(separator: "/").map(String.init)
        if !path.isEmpty { object["path"] = path }
        if let query = components.queryItems, !query.isEmpty {
            object["query"] = query.map { ["key": $0.name, "value": $0.value ?? ""] }
        }
        return object
    }
}

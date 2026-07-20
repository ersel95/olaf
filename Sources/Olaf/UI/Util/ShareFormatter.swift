import Foundation

/// Produces share text (Simple/Full log formats). Pure functions → testable.
/// Content is taken **raw** from `LogEntry`/`NetworkLogInfo` (no masking) → may contain sensitive
/// data; the responsibility for sharing lies with the user.
enum ShareFormatter {

    // MARK: - Network

    /// "Simple Log": summary + headers (no body).
    static func simpleNetworkLog(entry: LogEntry, info: NetworkLogInfo) -> String {
        var lines: [String] = []
        lines.append("\(info.method ?? "GET") \(info.url ?? "-")")
        if let status = info.statusCode { lines.append("Status: \(status)") }
        if let error = info.error { lines.append("Error: \(error)") }
        if let ms = info.durationMs { lines.append("Duration: \(ms) ms") }
        if let b = info.requestBytes { lines.append("Request size: \(Formatting.byteCount(b))") }
        if let b = info.responseBytes { lines.append("Response size: \(Formatting.byteCount(b))") }
        lines.append("Time: \(entry.date.formatted(date: .numeric, time: .standard))")

        if !info.requestHeaders.isEmpty {
            lines.append("\n-- Request Headers --")
            lines.append(contentsOf: info.requestHeaders.map { "\($0.key): \($0.value)" })
        }
        if !info.responseHeaders.isEmpty {
            lines.append("\n-- Response Headers --")
            lines.append(contentsOf: info.responseHeaders.map { "\($0.key): \($0.value)" })
        }
        return lines.joined(separator: "\n")
    }

    /// "Full Log": Simple + request/response bodies + cURL.
    static func fullNetworkLog(entry: LogEntry, info: NetworkLogInfo) -> String {
        var text = simpleNetworkLog(entry: entry, info: info)
        if let body = info.requestBody, !body.isEmpty {
            text += "\n\n-- Request Body --\n" + body
        }
        if let body = info.responseBody, !body.isEmpty {
            text += "\n\n-- Response Body --\n" + body
        }
        text += "\n\n-- cURL --\n" + CurlBuilder.curl(from: info)
        return text
    }

    // MARK: - Log

    /// Full text (multi-line) for a non-network entry.
    static func logDetail(entry: LogEntry) -> String {
        var lines: [String] = []
        lines.append("[\(entry.level.name)] [\(entry.category.rawValue)] \(entry.message)")
        lines.append("Time: \(entry.date.formatted(date: .numeric, time: .standard))")
        lines.append("Thread: \(entry.thread)")
        lines.append("Source: \(entry.fileName):\(entry.line) — \(entry.function)")
        if !entry.metadata.isEmpty {
            lines.append("\n-- Metadata --")
            lines.append(contentsOf: entry.metadata.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" })
        }
        return lines.joined(separator: "\n")
    }
}

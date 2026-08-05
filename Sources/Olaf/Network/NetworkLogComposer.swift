import Foundation

/// Raw data of a network event (no redaction/filtering — logged as-is).
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
    /// The request was cancelled before completing (`NSURLErrorCancelled` — e.g. screen dismissed,
    /// prefetch abandoned). Not a real error; logged at `.info` level, `error` field stays empty.
    var cancelled: Bool = false
    /// Timing breakdown derived from `URLSessionTaskMetrics` (`nil` if it couldn't be collected).
    var timing: NetworkTimingMetrics?
    /// `image/*` response body (base64) — only populated for images under the
    /// `maxImageBodyBytes` limit; shown as a preview in the viewer detail.
    var responseImageBase64: String?
    /// The response was produced by a mock (no network call — see `OlafMockResponse`).
    var mocked: Bool = false
}

/// A request's phase-by-phase timing breakdown (answers "is it the API that's slow, or the network?").
/// DNS/connect/TLS phases are naturally empty for reused connections.
struct NetworkTimingMetrics: Sendable {
    var dnsMs: Int?
    var connectMs: Int?
    var tlsMs: Int?
    /// Start of the request send → first byte of the response (time to first byte).
    var ttfbMs: Int?
    /// The protocol used (e.g. "h2", "http/1.1", "h3").
    var protocolName: String?
    /// Was an existing pooled connection reused (no new handshake)?
    var reusedConnection: Bool?
}

/// Converts a network event into level + message + metadata. Pure functions → testable.
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

    static func message(for event: NetworkLogEvent, redactor: (any OlafRedactor)? = nil) -> String {
        var parts = ["\(event.method)", redactor?.redact(url: event.url) ?? event.url]
        if let status = event.statusCode { parts.append("→ \(status)") }
        if event.cancelled { parts.append("→ cancelled") }
        if event.error != nil { parts.append("→ ✗") }
        if event.mocked { parts.append("[mock]") }
        parts.append("(\(event.durationMs)ms)")
        return parts.joined(separator: " ")
    }

    /// - Parameter redactor: masks bodies, headers and the URL before they become a stored record.
    ///   This is the **single** point where captured data turns into a log entry, so a host never
    ///   has to filter per endpoint. `nil` → everything is stored raw (the default).
    static func metadata(for event: NetworkLogEvent, redactor: (any OlafRedactor)? = nil) -> [String: String] {
        let requestURL = URL(string: event.url)
        var metadata: [String: String] = [
            "method": event.method,
            "url": redactor?.redact(url: event.url) ?? event.url,
            "durationMs": String(event.durationMs),
            "reqBytes": String(event.requestBytes),
            "respBytes": String(event.responseBytes)
        ]
        if let status = event.statusCode { metadata["status"] = String(status) }
        if let error = event.error { metadata["error"] = error }
        if event.cancelled { metadata["cancelled"] = "true" }
        if event.mocked { metadata["mocked"] = "true" }
        // Bodies live under separate `requestBody`/`responseBody` keys — raw unless a redactor
        // is configured, in which case they are masked here, before anything is stored or persisted.
        if let body = event.requestBody {
            metadata["requestBody"] = redactor?.redact(body: body, url: requestURL) ?? body
        }
        if let body = event.responseBody {
            metadata["responseBody"] = redactor?.redact(body: body, url: requestURL) ?? body
        }
        if let image = event.responseImageBase64 { metadata["responseImageBase64"] = image }
        // Headers get one key each, passed through the redactor by name.
        for (key, value) in event.requestHeaders ?? [:] {
            metadata["reqH.\(key)"] = redactor?.redact(headerValue: value, name: key, url: requestURL) ?? value
        }
        for (key, value) in event.responseHeaders ?? [:] {
            metadata["respH.\(key)"] = redactor?.redact(headerValue: value, name: key, url: requestURL) ?? value
        }
        // Timing breakdown is stored with a `t.` prefix (read by the viewer's "Timing" section).
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

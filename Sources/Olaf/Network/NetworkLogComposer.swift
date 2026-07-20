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

    static func message(for event: NetworkLogEvent) -> String {
        var parts = ["\(event.method)", event.url]
        if let status = event.statusCode { parts.append("→ \(status)") }
        if event.cancelled { parts.append("→ cancelled") }
        if event.error != nil { parts.append("→ ✗") }
        if event.mocked { parts.append("[mock]") }
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
        if event.mocked { metadata["mocked"] = "true" }
        // Bodies are stored raw under separate `requestBody`/`responseBody` keys.
        if let body = event.requestBody { metadata["requestBody"] = body }
        if let body = event.responseBody { metadata["responseBody"] = body }
        if let image = event.responseImageBase64 { metadata["responseImageBase64"] = image }
        // Headers are stored raw under separate keys.
        for (key, value) in event.requestHeaders ?? [:] { metadata["reqH.\(key)"] = value }
        for (key, value) in event.responseHeaders ?? [:] { metadata["respH.\(key)"] = value }
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

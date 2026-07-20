import Foundation

/// Produces a cURL representation from a `.network` entry. Header/body values are **raw** (no
/// masking); secrets, including `Authorization`/`Cookie`, pass through verbatim into the output —
/// review before sharing.
enum CurlBuilder {
    static func curl(from info: NetworkLogInfo) -> String {
        var lines = ["curl -X \(info.method ?? "GET") \(quote(info.url ?? ""))"]
        for header in info.requestHeaders {
            lines.append("-H \(quote("\(header.key): \(header.value)"))")
        }
        if let body = info.requestBody, !body.isEmpty {
            lines.append("-d \(quote(body))")
        }
        return lines.joined(separator: " \\\n  ")
    }

    /// Single-quoted shell argument; safely escapes any embedded single quotes.
    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

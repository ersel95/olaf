import Foundation

/// Masks sensitive values before a captured request is recorded.
///
/// Olaf itself knows nothing about *what* is sensitive — that is domain knowledge and belongs to
/// the host (this is a public repository; see the "no bank/company specifics" rule). The package
/// only guarantees *where* masking happens: every captured body and header passes through the
/// redactor in `NetworkLogComposer.metadata(for:redactor:)`, which is the single point where a
/// network event becomes a stored record. Nothing bypasses it, so a host never has to touch
/// individual call sites or endpoints.
///
/// Redaction runs at **capture time**: the raw value is masked before it reaches the ring buffer,
/// so it is never written to the NDJSON session file on disk.
///
/// ```swift
/// struct MyRedactor: OlafRedactor {
///     func redact(body: String, url: URL?) -> String { /* … */ }
/// }
///
/// var config = OlafNetworkConfiguration()
/// config.redactor = isLiveEnvironment ? MyRedactor() : nil   // nil → raw capture
/// ```
///
/// - Important: Masking is a *denylist*: a field the redactor does not recognise is stored raw.
///   When a build must not risk leaking anything, do not capture at all rather than relying on
///   a redactor — see ``OlafNetworkConfiguration``.
public protocol OlafRedactor: Sendable {

    /// Mask a request or response body. `url` is provided for endpoint-specific rules; most
    /// redactors ignore it and match on field names alone.
    func redact(body: String, url: URL?) -> String

    /// Mask a single header value. `name` is the header name as captured (original casing).
    func redact(headerValue: String, name: String, url: URL?) -> String

    /// Mask the URL itself — useful when sensitive values travel in the query string.
    func redact(url: String) -> String
}

public extension OlafRedactor {
    /// Default: headers pass through untouched.
    func redact(headerValue: String, name: String, url: URL?) -> String { headerValue }

    /// Default: the URL passes through untouched.
    func redact(url: String) -> String { url }
}

// MARK: - Key-based redactor

/// A ready-made ``OlafRedactor`` that masks values by **field name**, for JSON bodies, form bodies
/// and query strings. The field names come from the host, so the package stays domain-agnostic.
///
/// ```swift
/// let redactor = OlafKeyRedactor(keys: ["password", "otp", "balance", "iban"])
/// ```
///
/// Matching is case-insensitive and, by default, substring-based: `"balance"` also matches
/// `"availableBalance"` and `"balanceAmount"`. Nested objects and arrays are walked in full.
public struct OlafKeyRedactor: OlafRedactor {

    /// What to do with a body that could not be parsed as JSON or form data — the case where
    /// field-name matching cannot be applied reliably.
    public enum UnparsableBodyPolicy: Sendable {
        /// Replace the whole body with the placeholder. **The default**: fails closed, so an
        /// unrecognised format cannot leak a value that field matching never got to inspect.
        case maskEntirely
        /// Apply a best-effort textual pass for `key: value` / `key=value` shapes, and keep the
        /// rest of the body as-is. Preserves debuggability for non-JSON payloads at the cost of
        /// weaker guarantees.
        case bestEffort
        /// Store the body raw. Only for hosts that know their traffic is JSON-only.
        case keepRaw
    }

    /// Field names whose values get masked (lowercased at init).
    public let keys: [String]

    /// Header names whose values get masked entirely (lowercased at init).
    public let headerNames: [String]

    /// The text a masked value is replaced with.
    public let placeholder: String

    /// Whether a key matches as a substring (`true`, default) or must be exactly equal (`false`).
    public let matchesSubstrings: Bool

    /// Behaviour for bodies that are neither JSON nor form-encoded.
    public let unparsableBodyPolicy: UnparsableBodyPolicy

    public init(
        keys: [String],
        headerNames: [String] = ["authorization", "cookie", "set-cookie", "x-api-key"],
        placeholder: String = "***",
        matchesSubstrings: Bool = true,
        unparsableBodyPolicy: UnparsableBodyPolicy = .maskEntirely
    ) {
        self.keys = keys.map { $0.lowercased() }
        self.headerNames = headerNames.map { $0.lowercased() }
        self.placeholder = placeholder
        self.matchesSubstrings = matchesSubstrings
        self.unparsableBodyPolicy = unparsableBodyPolicy
    }

    /// Does this field name match one of the configured keys?
    public func matches(key: String) -> Bool {
        let candidate = key.lowercased()
        return matchesSubstrings
            ? keys.contains { candidate.contains($0) }
            : keys.contains(candidate)
    }

    // MARK: OlafRedactor

    public func redact(body: String, url: URL?) -> String {
        guard !body.isEmpty, !keys.isEmpty else { return body }

        if let json = redactJSON(body) { return json }
        if body.contains("=") && !body.contains("\n"), let form = redactFormBody(body) { return form }

        switch unparsableBodyPolicy {
        case .maskEntirely: return placeholder
        case .bestEffort: return redactTextually(body)
        case .keepRaw: return body
        }
    }

    public func redact(headerValue: String, name: String, url: URL?) -> String {
        headerNames.contains(name.lowercased()) || matches(key: name) ? placeholder : headerValue
    }

    public func redact(url: String) -> String {
        guard !keys.isEmpty,
              let separator = url.firstIndex(of: "?") else { return url }
        let base = String(url[url.startIndex..<separator])
        let query = String(url[url.index(after: separator)...])
        return base + "?" + redactQuery(query)
    }

    // MARK: - JSON

    /// Parses, walks and re-serialises the body. Returns `nil` when it isn't valid JSON (the body
    /// may be truncated by `maxBodyLength`, in which case the caller falls back to its policy).
    private func redactJSON(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }

        let redacted = redactJSONValue(parsed, maskAll: false)
        // Bodies are stored pretty-printed at capture time; keep that shape.
        guard let out = try? JSONSerialization.data(
            withJSONObject: redacted,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        ) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    /// Recursively walks the parsed JSON tree. `maskAll` is set once a matching key is found, so
    /// an entire nested object under e.g. `"balance"` is masked rather than just its scalar leaves.
    private func redactJSONValue(_ value: Any, maskAll: Bool) -> Any {
        if maskAll, !(value is [String: Any]), !(value is [Any]) { return placeholder }

        switch value {
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (key, nested) in dict {
                out[key] = redactJSONValue(nested, maskAll: maskAll || matches(key: key))
            }
            return out
        case let array as [Any]:
            return array.map { redactJSONValue($0, maskAll: maskAll) }
        default:
            return maskAll ? placeholder : value
        }
    }

    // MARK: - Form / query

    private func redactFormBody(_ body: String) -> String? {
        let redacted = redactQuery(body)
        return redacted == body && !body.contains("=") ? nil : redacted
    }

    private func redactQuery(_ query: String) -> String {
        query
            .split(separator: "&", omittingEmptySubsequences: false)
            .map { pair -> String in
                guard let equals = pair.firstIndex(of: "=") else { return String(pair) }
                let name = String(pair[pair.startIndex..<equals])
                return matches(key: name) ? "\(name)=\(placeholder)" : String(pair)
            }
            .joined(separator: "&")
    }

    // MARK: - Textual fallback

    /// Line-oriented `key: value` / `key = value` masking for bodies that parsed as neither JSON
    /// nor form data. Best-effort by definition — only used under `.bestEffort`.
    private func redactTextually(_ body: String) -> String {
        body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let separator = line.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                    return String(line)
                }
                let name = line[line.startIndex..<separator]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                guard matches(key: name) else { return String(line) }
                let leading = line.prefix { $0 == " " || $0 == "\t" }
                return "\(leading)\(name)\(line[separator]) \(placeholder)"
            }
            .joined(separator: "\n")
    }
}

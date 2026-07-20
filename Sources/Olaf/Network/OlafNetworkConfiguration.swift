import Foundation

/// Olaf network capture configuration.
public struct OlafNetworkConfiguration: Sendable {

    /// Also log request/response bodies. **On by default.** (Bodies are stored raw;
    /// set to `false` if not needed.)
    public var capturesBodies: Bool

    /// Also log request/response headers. **On by default** (headers are stored raw).
    public var capturesHeaders: Bool

    /// Maximum character count bodies are truncated to when logged.
    public var maxBodyLength: Int

    /// Upper limit (bytes) stored for **preview** of `image/*` response bodies. Images up to this
    /// size are appended to the record as base64 and shown on the detail screen; larger ones pass
    /// through with size info only (to avoid bloating RAM/disk). `0` → image preview disabled.
    public var maxImageBodyBytes: Int

    /// The category network records are logged under.
    public var category: LogCategory

    /// **Only** requests whose URL contains one of these parts (host/path) are captured. Empty = all.
    /// E.g. to capture only your own API: `["api-gateway", "myapp.com"]`.
    public var includedURLs: [String]

    /// Requests containing these URL parts are **skipped** (not captured — the request passes through as-is).
    /// E.g. to hide SDK noise: `["firebaseio", "crashlytics", "googleapis", "app-measurement"]`.
    public var excludedURLs: [String]

    /// Accept the server certificate unconditionally, **for the capture proxy only**. **`false` by default**
    /// (safe: system validation). Capture re-sends the request from its own URLSession; if the host trusts
    /// its own custom CA (e.g. an internal test gateway) or uses pinning, default system validation will
    /// reject that traffic (TLS -9807). If the host already trusts this traffic, set this to `true`
    /// (**non-prod only**) so capture accepts the certificates the host trusts. Olaf is already compiled
    /// under `#if !PROD`; live traffic is unaffected. NEVER enable in prod.
    public var allowsArbitraryServerTrustForCapture: Bool

    public init(
        capturesBodies: Bool = true,
        capturesHeaders: Bool = true,
        maxBodyLength: Int = 8000,
        maxImageBodyBytes: Int = 262_144,   // 256 KB
        category: LogCategory = .network,
        includedURLs: [String] = [],
        excludedURLs: [String] = [],
        allowsArbitraryServerTrustForCapture: Bool = false
    ) {
        self.capturesBodies = capturesBodies
        self.capturesHeaders = capturesHeaders
        self.maxBodyLength = max(0, maxBodyLength)
        self.maxImageBodyBytes = max(0, maxImageBodyBytes)
        self.category = category
        self.includedURLs = includedURLs.map { $0.lowercased() }
        self.excludedURLs = excludedURLs.map { $0.lowercased() }
        self.allowsArbitraryServerTrustForCapture = allowsArbitraryServerTrustForCapture
    }

    /// Should this URL be captured? (allow/deny filter — used in `OlafURLProtocol.canInit`)
    public func shouldCapture(_ url: URL?) -> Bool {
        guard let target = url?.absoluteString.lowercased() else { return includedURLs.isEmpty }
        if excludedURLs.contains(where: { target.contains($0) }) { return false }
        if !includedURLs.isEmpty { return includedURLs.contains(where: { target.contains($0) }) }
        return true
    }

    public static let `default` = OlafNetworkConfiguration()
}

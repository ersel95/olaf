import Foundation

/// `GET /config?appKey=` yanıtı (server-side kill-switch).
public struct OlafRemoteConfig: Codable, Sendable {

    /// Server-side kill-switch. `false` → cihaz raporu yine sıkıştırıp **göndermez**
    /// (ikinci savunma katmanı; local `enabled` ile birlikte iki gate).
    public let captureEnabled: Bool

    /// Screenshot için izin verilen üst sınır (byte).
    public let maxScreenshotBytes: Int

    public init(captureEnabled: Bool, maxScreenshotBytes: Int) {
        self.captureEnabled = captureEnabled
        self.maxScreenshotBytes = maxScreenshotBytes
    }

    private enum CodingKeys: String, CodingKey {
        case captureEnabled, maxScreenshotBytes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        captureEnabled = try c.decodeIfPresent(Bool.self, forKey: .captureEnabled) ?? false
        maxScreenshotBytes = try c.decodeIfPresent(Int.self, forKey: .maxScreenshotBytes) ?? (4 * 1_048_576)
    }

    /// Henüz config çekilmediğinde / hata durumunda kullanılan güvenli varsayılan: **kapalı**.
    public static let disabled = OlafRemoteConfig(
        captureEnabled: false,
        maxScreenshotBytes: 4 * 1_048_576
    )
}

/// Remote config'i çeken istemci. **Yalnız `enabled == true` iken** kullanılır.
/// Kendi `URLSession`'ını kullanır (OlafURLProtocol enjekte edilmez → recursion yok).
final class OlafRemoteConfigClient: @unchecked Sendable {

    private let configuration: OlafUploadConfiguration
    private let session: URLSession

    init(configuration: OlafUploadConfiguration) {
        self.configuration = configuration
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfig.protocolClasses = []         // capture protokolleri enjekte edilmez
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: sessionConfig)
    }

    /// `GET /config` (app, x-olaf-api-key'den çözülür). Hata/ulaşılamaz → `.disabled` (güvenli taraf).
    func fetch() async -> OlafRemoteConfig {
        var request = URLRequest(url: configuration.configURL)
        request.httpMethod = "GET"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-olaf-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .disabled
            }
            return try JSONDecoder().decode(OlafRemoteConfig.self, from: data)
        } catch {
            return .disabled
        }
    }
}

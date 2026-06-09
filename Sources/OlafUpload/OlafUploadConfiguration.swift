import Foundation

/// Bug-reporter (upload) yapılandırması. `OlafUpload.configure(...)` ile bir kez verilir.
///
/// ⚠️ **Public repo kuralı**: Hiçbir gerçek URL / şirket adı / sır bu yapıya gömülü
/// **default** değer olarak girmez. `apiKey` / `baseURL` host uygulama tarafından
/// runtime'da (xcconfig/secrets) sağlanır.
public struct OlafUploadConfiguration: Sendable {

    /// Özelliğin yerel (build-time) aç/kapa anahtarı. **Varsayılan `false` (opt-in).**
    /// `false` iken `OlafUpload.configure` erken döner: sıfır ağ / detector / tracker.
    public var enabled: Bool

    /// Ingestion auth sırrı. `x-olaf-api-key` header'ı olarak gönderilir. Backend app'i
    /// bu key'den tanır (apiKey benzersiz → ayrıca appKey/slug taşımaya gerek yok).
    /// Boşsa configure no-op olur.
    public var apiKey: String

    /// Olaf backend kök adresi (örn. `https://olaf-api.example.com`). Host tarafından sağlanır.
    public var baseURL: URL

    /// Ortam etiketi (örn. "staging" / "uat"). Rapor meta'sına yazılır.
    public var environment: String

    /// `POST /reports` upload yolu (baseURL'e göre relative).
    public var reportsPath: String

    /// `GET /config` remote config yolu (baseURL'e göre relative).
    public var configPath: String

    /// Tek bir isteğin zaman aşımı (saniye).
    public var requestTimeout: TimeInterval

    /// Offline kuyruğunda bir rapor için en fazla deneme sayısı.
    public var maxRetryCount: Int

    /// Exponential backoff taban gecikmesi (saniye). Deneme n → `baseRetryDelay * 2^n`.
    public var baseRetryDelay: TimeInterval

    /// Screenshot JPEG sıkıştırma kalitesi (0...1). Backend `bodyLimit`'ini aşmamak için ~0.7.
    public var screenshotJPEGQuality: Double

    /// Screenshot için izin verilen üst sınır (byte). Remote config `maxScreenshotBytes` ile ezilebilir.
    public var maxScreenshotBytes: Int

    public init(
        enabled: Bool = false,
        apiKey: String = "",
        baseURL: URL,
        environment: String = "staging",
        // Backend exposes ingestion under the API global prefix + `olaf` namespace.
        // Host passes the bare origin baseURL (e.g. https://olaf-api.example.com);
        // override these paths only if the backend is mounted elsewhere.
        reportsPath: String = "/api/v1/olaf/reports",
        configPath: String = "/api/v1/olaf/config",
        requestTimeout: TimeInterval = 30,
        maxRetryCount: Int = 5,
        baseRetryDelay: TimeInterval = 5,
        screenshotJPEGQuality: Double = 0.7,
        maxScreenshotBytes: Int = 4 * 1_048_576
    ) {
        self.enabled = enabled
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.environment = environment
        self.reportsPath = reportsPath
        self.configPath = configPath
        self.requestTimeout = max(1, requestTimeout)
        self.maxRetryCount = max(0, maxRetryCount)
        self.baseRetryDelay = max(0, baseRetryDelay)
        self.screenshotJPEGQuality = min(1, max(0.1, screenshotJPEGQuality))
        self.maxScreenshotBytes = max(0, maxScreenshotBytes)
    }

    /// `POST /reports` tam URL'i.
    public var reportsURL: URL {
        url(appending: reportsPath)
    }

    /// `GET /config` tam URL'i. App, `x-olaf-api-key` header'ından çözülür (query yok).
    public var configURL: URL {
        url(appending: configPath)
    }

    /// Recursion önleme için `OlafNetwork.excludedURLs`'e eklenecek host/path parçaları.
    var captureExclusionFragments: [String] {
        var fragments: [String] = []
        if let host = baseURL.host { fragments.append(host.lowercased()) }
        fragments.append(reportsPath.lowercased())
        fragments.append(configPath.lowercased())
        return fragments.filter { !$0.isEmpty }
    }

    private func url(appending path: String) -> URL {
        let trimmedBase = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        return URL(string: trimmedBase + normalizedPath) ?? baseURL
    }
}

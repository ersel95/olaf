import Foundation

/// Eşleşen isteklere **ağa çıkılmadan** döndürülecek sahte yanıt (response mocking).
///
/// Edge-case'leri gerçek backend'e dokunmadan test etmeyi sağlar: hata gövdeleri, boş listeler,
/// 5xx senaryoları, yavaş yanıt (`delaySeconds`) veya taşıma hatası (`transportError` — örn.
/// internet yok). Mock'lanan istekler `.network` kategorisine normal şekilde loglanır ve
/// detayda "Mock" olarak işaretlenir.
///
/// ```swift
/// OlafNetwork.addMock(OlafMockResponse(
///     urlContains: "/v1/accounts",
///     json: #"{"accounts": []}"#
/// ))
/// OlafNetwork.addMock(.failure(urlContains: "/v1/transfer", error: .timedOut, delaySeconds: 3))
/// ```
///
/// Eşleşme: URL (lowercase) `urlContains` parçasını içeriyorsa ve `method` uyuyorsa
/// (nil = tüm metotlar). Birden çok mock eşleşirse **ilk eklenen** kazanır.
/// Capture filtreleri (`includedURLs`/`excludedURLs`) mock'ları etkilemez.
public struct OlafMockResponse: Sendable {

    /// URL'in içermesi gereken parça (karşılaştırma lowercase yapılır).
    public var urlContains: String
    /// Eşleşecek HTTP metodu (`nil` = tümü). Karşılaştırma büyük harfle yapılır.
    public var method: String?
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data
    /// Yanıt bu kadar saniye geciktirilir (yavaş ağ simülasyonu; bekleyen istek barında görünür).
    public var delaySeconds: TimeInterval
    /// Set ise HTTP yanıtı yerine **taşıma hatası** döner (örn. `.notConnectedToInternet`).
    public var transportError: URLError.Code?

    public init(
        urlContains: String,
        method: String? = nil,
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: Data = Data(),
        delaySeconds: TimeInterval = 0,
        transportError: URLError.Code? = nil
    ) {
        self.urlContains = urlContains.lowercased()
        self.method = method?.uppercased()
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.delaySeconds = max(0, delaySeconds)
        self.transportError = transportError
    }

    /// JSON gövdeli mock için kısayol (`Content-Type: application/json`).
    public init(
        urlContains: String,
        method: String? = nil,
        statusCode: Int = 200,
        json: String,
        delaySeconds: TimeInterval = 0
    ) {
        self.init(
            urlContains: urlContains,
            method: method,
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: Data(json.utf8),
            delaySeconds: delaySeconds
        )
    }

    /// Taşıma hatası mock'u için kısayol (yanıt yok; URLError fırlar).
    public static func failure(
        urlContains: String,
        method: String? = nil,
        error: URLError.Code = .notConnectedToInternet,
        delaySeconds: TimeInterval = 0
    ) -> OlafMockResponse {
        OlafMockResponse(
            urlContains: urlContains,
            method: method,
            delaySeconds: delaySeconds,
            transportError: error
        )
    }

    /// Bu mock verilen isteğe uyuyor mu?
    func matches(_ request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString.lowercased(), url.contains(urlContains) else {
            return false
        }
        guard let method else { return true }
        return method == (request.httpMethod ?? "GET").uppercased()
    }
}

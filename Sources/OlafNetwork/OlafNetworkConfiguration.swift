import Foundation
import OlafCore

/// Olaf network capture yapılandırması.
public struct OlafNetworkConfiguration: Sendable {

    /// İstek/yanıt gövdelerini de logla. **Varsayılan açık.** (Gövdeler yine BankingRedactor'dan
    /// geçer; yine de keyfi JSON'daki her PII garanti yakalanamaz — gerekirse `false` yapın.)
    public var capturesBodies: Bool

    /// İstek/yanıt header'larını da logla. **Varsayılan açık** (hassas header'lar redaksiyondan geçer).
    public var capturesHeaders: Bool

    /// Gövde loglanırken kesilecek maksimum karakter sayısı.
    public var maxBodyLength: Int

    /// Network kayıtlarının düşeceği kategori.
    public var category: LogCategory

    /// **Yalnız bu** URL parçalarını (host/path) içeren istekler yakalanır. Boş = tümü.
    /// Örn. yalnız kendi API'niz: `["api-gateway", "myapp.com"]`.
    public var includedURLs: [String]

    /// Bu URL parçalarını içeren istekler **atlanır** (yakalanmaz — istek olduğu gibi geçer).
    /// Örn. SDK gürültüsünü gizlemek: `["firebaseio", "crashlytics", "googleapis", "app-measurement"]`.
    public var excludedURLs: [String]

    public init(
        capturesBodies: Bool = true,
        capturesHeaders: Bool = true,
        maxBodyLength: Int = 8000,
        category: LogCategory = .network,
        includedURLs: [String] = [],
        excludedURLs: [String] = []
    ) {
        self.capturesBodies = capturesBodies
        self.capturesHeaders = capturesHeaders
        self.maxBodyLength = max(0, maxBodyLength)
        self.category = category
        self.includedURLs = includedURLs.map { $0.lowercased() }
        self.excludedURLs = excludedURLs.map { $0.lowercased() }
    }

    /// Bu URL yakalanmalı mı? (allow/deny filtresi — `OlafURLProtocol.canInit`'te kullanılır)
    public func shouldCapture(_ url: URL?) -> Bool {
        guard let target = url?.absoluteString.lowercased() else { return includedURLs.isEmpty }
        if excludedURLs.contains(where: { target.contains($0) }) { return false }
        if !includedURLs.isEmpty { return includedURLs.contains(where: { target.contains($0) }) }
        return true
    }

    public static let `default` = OlafNetworkConfiguration()
}

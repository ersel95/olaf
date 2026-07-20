import Foundation

/// Olaf network capture cephesi. Uygulamanın network isteklerini yakalayıp `.network`
/// kategorisinde **ham** (maskelemesiz) Olaf'a loglar.
///
/// ```swift
/// // Tüm istekleri yakalamak için (Alamofire/URLSession custom config):
/// OlafNetwork.install(into: sessionConfiguration)
///
/// // Başka bir capture aracıyla BİRLİKTE çalışmak için zincirle:
/// OlafNetwork.install(into: sessionConfiguration, chainingTo: [OtherCaptureProtocol.self])
/// ```
public enum OlafNetwork {

    private static let box = ConfigBox()

    /// Aktif yapılandırma. `Olaf.start` öncesi/sonrası ayarlanabilir.
    public static var configuration: OlafNetworkConfiguration {
        get { box.value }
        set { box.value = newValue }
    }

    /// Olaf isteği yeniden başlatırken kendi (yakalanmayan) proxy session'ına eklenecek
    /// ek `URLProtocol` sınıfları. Başka capture araçlarının da yakalaması için kullanılır.
    public static var chainedProtocolClasses: [AnyClass] {
        get { box.chained }
        set { box.chained = newValue }
    }

    /// Yakalama protokolünü verilen `URLSessionConfiguration`'a enjekte eder ve yakalama
    /// parametrelerini **init'te** ayarlar.
    /// - Parameters:
    ///   - configuration: Protokolün başa ekleneceği session config.
    ///   - networkConfiguration: Yakalama filtreleri (gövde/header default açık).
    ///   - chainingTo: Olaf yakaladıktan sonra isteğin geçmesi gereken ek `URLProtocol`'ler
    ///     — böylece başka bir capture aracı da aynı trafiği yakalar.
    public static func install(
        into configuration: URLSessionConfiguration,
        with networkConfiguration: OlafNetworkConfiguration = .default,
        chainingTo chainedClasses: [AnyClass] = []
    ) {
        self.configuration = networkConfiguration
        self.chainedProtocolClasses = chainedClasses
        // Var olan kopyaları ele, garantili en öne ekle (URLProtocol "ilk eşleşen kazanır").
        let id = ObjectIdentifier(OlafURLProtocol.self)
        var classes = (configuration.protocolClasses ?? []).filter { ObjectIdentifier($0) != id }
        classes.insert(OlafURLProtocol.self, at: 0)
        configuration.protocolClasses = classes
    }

    /// `URLSession.shared` ve global istekler için protokolü kaydeder ve yakalama parametrelerini init'te ayarlar.
    public static func installGlobally(
        _ networkConfiguration: OlafNetworkConfiguration = .default,
        chainingTo chainedClasses: [AnyClass] = []
    ) {
        self.configuration = networkConfiguration
        self.chainedProtocolClasses = chainedClasses
        URLProtocol.registerClass(OlafURLProtocol.self)
    }

    /// **En kolay kurulum — host networking koduna DOKUNMADAN.**
    /// `URLSessionConfiguration.default/.ephemeral` swizzle edilerek tüm session'lara (Alamofire dahil)
    /// otomatik enjekte edilir + shared session için global kayıt yapılır.
    ///
    /// SSL: proxy session **varsayılan sistem doğrulaması** kullanır (pinning/OS trust baypaslanmaz);
    /// özel kurumsal CA'lar için `allowsArbitraryServerTrustForCapture` (yalnız non-prod). **Non-prod debug** için.
    ///
    /// ```swift
    /// // OlafManager.initialize() içinde tek satır — BaseService'e dokunmaya gerek yok:
    /// OlafNetwork.startAutomaticCapture()
    /// ```
    public static func startAutomaticCapture(_ networkConfiguration: OlafNetworkConfiguration = .default) {
        self.configuration = networkConfiguration
        URLSessionConfiguration.olafEnableAutomaticInjection()
        URLProtocol.registerClass(OlafURLProtocol.self)
    }

    /// Global kaydı kaldırır.
    public static func uninstallGlobally() {
        URLProtocol.unregisterClass(OlafURLProtocol.self)
    }

    /// Manuel enjeksiyon için protokol sınıfı.
    public static var protocolClass: AnyClass { OlafURLProtocol.self }

    /// Şu an devam eden (henüz tamamlanmamış) yakalamalar — en eski üstte.
    /// Viewer "Aktif istekler" bölümü bunu periyodik okur; asılı kalan istekler burada görünür.
    public static var pendingRequests: [PendingNetworkRequest] {
        PendingRequestRegistry.shared.snapshot
    }

    // MARK: - Response mocking

    /// Bir mock kaydeder. Eşleşen istekler **ağa çıkmadan** bu yanıtı alır (capture aktif olmalı —
    /// `startAutomaticCapture`/`install`). Birden çok mock eşleşirse ilk eklenen kazanır.
    /// Yalnız non-prod debug içindir (Olaf'ın geri kalanı gibi `#if !PROD` altında kalmalı).
    public static func addMock(_ mock: OlafMockResponse) {
        box.mocks.append(mock)
    }

    /// Tüm mock'ları kaldırır (istekler yeniden gerçek backend'e gider).
    public static func removeAllMocks() {
        box.mocks = []
    }

    /// Kayıtlı mock'lar (ekleme sırasıyla).
    public static var activeMocks: [OlafMockResponse] {
        box.mocks
    }

    /// Verilen isteğe uyan ilk mock (dahili — `OlafURLProtocol` kullanır).
    static func mock(for request: URLRequest) -> OlafMockResponse? {
        let mocks = box.mocks
        guard !mocks.isEmpty else { return nil }
        return mocks.first { $0.matches(request) }
    }

    // Dahili erişim (URLProtocol config'i okur).
    static var current: OlafNetworkConfiguration { box.value }

    private final class ConfigBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = OlafNetworkConfiguration.default
        private var _chained: [AnyClass] = []
        private var _mocks: [OlafMockResponse] = []

        var value: OlafNetworkConfiguration {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
        var chained: [AnyClass] {
            get { lock.lock(); defer { lock.unlock() }; return _chained }
            set { lock.lock(); _chained = newValue; lock.unlock() }
        }
        var mocks: [OlafMockResponse] {
            get { lock.lock(); defer { lock.unlock() }; return _mocks }
            set { lock.lock(); _mocks = newValue; lock.unlock() }
        }
    }
}

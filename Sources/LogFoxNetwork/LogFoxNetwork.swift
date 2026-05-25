import Foundation

/// LogFox network capture cephesi. Uygulamanın network isteklerini yakalayıp `.network`
/// kategorisinde (redakte edilerek) LogFox'a loglar.
///
/// ```swift
/// // Tüm istekleri yakalamak için (Alamofire/URLSession custom config):
/// LogFoxNetwork.install(into: sessionConfiguration)
///
/// // Netfox gibi başka bir capture aracıyla BİRLİKTE çalışmak için zincirle:
/// LogFoxNetwork.install(into: sessionConfiguration, chainingTo: [NFXProtocol.self])
/// ```
public enum LogFoxNetwork {

    private static let box = ConfigBox()

    /// Aktif yapılandırma. `LogFox.start` öncesi/sonrası ayarlanabilir.
    public static var configuration: LogFoxNetworkConfiguration {
        get { box.value }
        set { box.value = newValue }
    }

    /// LogFox isteği yeniden başlatırken kendi (yakalanmayan) proxy session'ına eklenecek
    /// ek `URLProtocol` sınıfları. Netfox/başka capture araçlarının da yakalaması için kullanılır.
    public static var chainedProtocolClasses: [AnyClass] {
        get { box.chained }
        set { box.chained = newValue }
    }

    /// Yakalama protokolünü verilen `URLSessionConfiguration`'a enjekte eder ve yakalama
    /// parametrelerini **init'te** ayarlar (mevcut `NFXProtocol` enjeksiyonuyla aynı patern).
    /// - Parameters:
    ///   - configuration: Protokolün başa ekleneceği session config.
    ///   - networkConfiguration: Yakalama filtreleri (gövde/header default açık).
    ///   - chainingTo: LogFox yakaladıktan sonra isteğin geçmesi gereken ek `URLProtocol`'ler
    ///     (örn. `[NFXProtocol.self]`) — böylece Netfox de aynı trafiği yakalar.
    public static func install(
        into configuration: URLSessionConfiguration,
        with networkConfiguration: LogFoxNetworkConfiguration = .default,
        chainingTo chainedClasses: [AnyClass] = []
    ) {
        self.configuration = networkConfiguration
        self.chainedProtocolClasses = chainedClasses
        // Var olan kopyaları ele, garantili en öne ekle (URLProtocol "ilk eşleşen kazanır").
        let id = ObjectIdentifier(LogFoxURLProtocol.self)
        var classes = (configuration.protocolClasses ?? []).filter { ObjectIdentifier($0) != id }
        classes.insert(LogFoxURLProtocol.self, at: 0)
        configuration.protocolClasses = classes
    }

    /// `URLSession.shared` ve global istekler için protokolü kaydeder ve yakalama parametrelerini init'te ayarlar.
    public static func installGlobally(
        _ networkConfiguration: LogFoxNetworkConfiguration = .default,
        chainingTo chainedClasses: [AnyClass] = []
    ) {
        self.configuration = networkConfiguration
        self.chainedProtocolClasses = chainedClasses
        URLProtocol.registerClass(LogFoxURLProtocol.self)
    }

    /// **En kolay kurulum (Netfox tarzı) — host networking koduna DOKUNMADAN.**
    /// `URLSessionConfiguration.default/.ephemeral` swizzle edilerek tüm session'lara (Alamofire dahil)
    /// otomatik enjekte edilir + shared session için global kayıt yapılır.
    ///
    /// SSL: proxy session sunucu trust'ını kabul eder (iç/pinned sertifikalar kırılmaz). **Non-prod debug** için.
    ///
    /// ```swift
    /// // LogFoxManager.initialize() içinde tek satır — BaseService'e dokunmaya gerek yok:
    /// LogFoxNetwork.startAutomaticCapture()
    /// ```
    public static func startAutomaticCapture(_ networkConfiguration: LogFoxNetworkConfiguration = .default) {
        self.configuration = networkConfiguration
        URLSessionConfiguration.logfoxEnableAutomaticInjection()
        URLProtocol.registerClass(LogFoxURLProtocol.self)
    }

    /// Global kaydı kaldırır.
    public static func uninstallGlobally() {
        URLProtocol.unregisterClass(LogFoxURLProtocol.self)
    }

    /// Manuel enjeksiyon için protokol sınıfı.
    public static var protocolClass: AnyClass { LogFoxURLProtocol.self }

    // Dahili erişim (URLProtocol config'i okur).
    static var current: LogFoxNetworkConfiguration { box.value }

    private final class ConfigBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = LogFoxNetworkConfiguration.default
        private var _chained: [AnyClass] = []

        var value: LogFoxNetworkConfiguration {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
        var chained: [AnyClass] {
            get { lock.lock(); defer { lock.unlock() }; return _chained }
            set { lock.lock(); _chained = newValue; lock.unlock() }
        }
    }
}

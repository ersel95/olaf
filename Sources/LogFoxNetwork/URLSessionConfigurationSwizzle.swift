import Foundation
import ObjectiveC

/// `URLSessionConfiguration.default` / `.ephemeral` getter'larını swizzle ederek, uygulamada
/// oluşturulan TÜM session config'lerine `LogFoxURLProtocol`'ü otomatik enjekte eder.
/// Böylece host'un networking koduna (BaseService vb.) **hiç dokunmadan** capture aktifleşir
/// (Netfox'un tek-satır kurulum yaklaşımıyla aynı mantık).
extension URLSessionConfiguration {

    private static let logfoxSwizzleOnce: Void = {
        let cls: AnyClass = URLSessionConfiguration.self
        func swap(_ original: Selector, _ swizzled: Selector) {
            guard let originalMethod = class_getClassMethod(cls, original),
                  let swizzledMethod = class_getClassMethod(cls, swizzled) else { return }
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
        swap(NSSelectorFromString("defaultSessionConfiguration"), #selector(logfox_defaultSessionConfiguration))
        swap(NSSelectorFromString("ephemeralSessionConfiguration"), #selector(logfox_ephemeralSessionConfiguration))
    }()

    /// Swizzle'ı bir kez etkinleştirir (idempotent).
    static func logfoxEnableAutomaticInjection() {
        _ = logfoxSwizzleOnce
    }

    // Exchange sonrası bu metod orijinal `defaultSessionConfiguration`'a karşılık gelir.
    @objc class func logfox_defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = logfox_defaultSessionConfiguration() // artık orijinal impl
        configuration.logfoxInjectProtocol()
        return configuration
    }

    @objc class func logfox_ephemeralSessionConfiguration() -> URLSessionConfiguration {
        let configuration = logfox_ephemeralSessionConfiguration()
        configuration.logfoxInjectProtocol()
        return configuration
    }

    private func logfoxInjectProtocol() {
        var classes = protocolClasses ?? []
        let id = ObjectIdentifier(LogFoxURLProtocol.self)
        guard !classes.contains(where: { ObjectIdentifier($0) == id }) else { return }
        classes.insert(LogFoxURLProtocol.self, at: 0)
        protocolClasses = classes
    }
}

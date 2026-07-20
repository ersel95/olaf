import Foundation
import ObjectiveC

/// `URLSessionConfiguration.default` / `.ephemeral` getter'larını swizzle ederek, uygulamada
/// oluşturulan TÜM session config'lerine `OlafURLProtocol`'ü otomatik enjekte eder.
/// Böylece host'un networking koduna (BaseService vb.) **hiç dokunmadan** capture aktifleşir
/// (tek-satır, sıfır-dokunuş kurulum yaklaşımı).
extension URLSessionConfiguration {

    private static let olafSwizzleOnce: Void = {
        let cls: AnyClass = URLSessionConfiguration.self
        func swap(_ original: Selector, _ swizzled: Selector) {
            guard let originalMethod = class_getClassMethod(cls, original),
                  let swizzledMethod = class_getClassMethod(cls, swizzled) else { return }
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
        swap(NSSelectorFromString("defaultSessionConfiguration"), #selector(olaf_defaultSessionConfiguration))
        swap(NSSelectorFromString("ephemeralSessionConfiguration"), #selector(olaf_ephemeralSessionConfiguration))
    }()

    /// Swizzle'ı bir kez etkinleştirir (idempotent).
    static func olafEnableAutomaticInjection() {
        _ = olafSwizzleOnce
    }

    // Exchange sonrası bu metod orijinal `defaultSessionConfiguration`'a karşılık gelir.
    @objc class func olaf_defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = olaf_defaultSessionConfiguration() // artık orijinal impl
        configuration.olafInjectProtocol()
        return configuration
    }

    @objc class func olaf_ephemeralSessionConfiguration() -> URLSessionConfiguration {
        let configuration = olaf_ephemeralSessionConfiguration()
        configuration.olafInjectProtocol()
        return configuration
    }

    private func olafInjectProtocol() {
        var classes = protocolClasses ?? []
        let id = ObjectIdentifier(OlafURLProtocol.self)
        guard !classes.contains(where: { ObjectIdentifier($0) == id }) else { return }
        classes.insert(OlafURLProtocol.self, at: 0)
        protocolClasses = classes
    }
}

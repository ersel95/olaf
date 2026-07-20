import Foundation
import ObjectiveC

/// Swizzles the `URLSessionConfiguration.default` / `.ephemeral` getters to automatically inject
/// `OlafURLProtocol` into EVERY session config created in the app.
/// This activates capture **without touching** the host's networking code (BaseService etc.) at all
/// (a one-line, zero-touch setup approach).
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

    /// Activates the swizzle once (idempotent).
    static func olafEnableAutomaticInjection() {
        _ = olafSwizzleOnce
    }

    // After the exchange, this method corresponds to the original `defaultSessionConfiguration`.
    @objc class func olaf_defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = olaf_defaultSessionConfiguration() // now the original impl
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

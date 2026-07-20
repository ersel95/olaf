#if canImport(UIKit)
import UIKit
import ObjectiveC

public extension Notification.Name {
    /// Cihaz sallandığında gönderilir. `OlafPresenter` bunu dinler.
    static let olafShake = Notification.Name("com.olaf.shake")
}

/// Sallama algılama: `UIWindow.motionEnded` **runtime swizzle** ile yapılır.
/// (Salt extension-override SPM statik kütüphanede dead-strip edilip ObjC runtime'a kaydolmayabilir;
/// swizzle `install()`'dan çağrıldığı için referanslı kalır.)
enum ShakeDetector {

    private typealias MotionEndedIMP = @convention(c) (AnyObject, Selector, UIEvent.EventSubtype, UIEvent?) -> Void

    /// `UIWindow.motionEnded`'i bir kez swizzle eder; shake'te `.olafShake` post eder, sonra orijinali çağırır.
    static func install() {
        let selector = #selector(UIResponder.motionEnded(_:with:))
        guard let method = class_getInstanceMethod(UIWindow.self, selector) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: MotionEndedIMP.self)
        let typeEncoding = method_getTypeEncoding(method)

        let block: @convention(block) (AnyObject, UIEvent.EventSubtype, UIEvent?) -> Void = { receiver, motion, event in
            if motion == .motionShake {
                NotificationCenter.default.post(name: .olafShake, object: nil)
            }
            original(receiver, selector, motion, event)
        }
        class_replaceMethod(UIWindow.self, selector, imp_implementationWithBlock(block), typeEncoding)
    }
}
#endif

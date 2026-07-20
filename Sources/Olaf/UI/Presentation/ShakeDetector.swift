#if canImport(UIKit)
import UIKit
import ObjectiveC

public extension Notification.Name {
    /// Sent when the device is shaken. `OlafPresenter` listens for this.
    static let olafShake = Notification.Name("com.olaf.shake")
}

/// Shake detection: implemented via **runtime swizzling** of `UIWindow.motionEnded`.
/// (A plain extension-override could be dead-stripped in an SPM static library and never
/// register with the ObjC runtime; the swizzle stays referenced because it's called from `install()`.)
enum ShakeDetector {

    private typealias MotionEndedIMP = @convention(c) (AnyObject, Selector, UIEvent.EventSubtype, UIEvent?) -> Void

    /// Swizzles `UIWindow.motionEnded` once; posts `.olafShake` on shake, then calls the original.
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

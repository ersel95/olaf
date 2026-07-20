#if canImport(UIKit)
import UIKit
import SwiftUI

/// Presents the viewer in a **separate `UIWindow`**, without touching the app's own
/// navigation/coordinator structure. This way it works conflict-free in every project.
@MainActor
final class OlafPresenter {

    static let shared = OlafPresenter()

    private var window: UIWindow?
    private var shakeObserver: NSObjectProtocol?

    private init() {}

    var isPresented: Bool { window != nil }

    /// Sets up the shake → open/close observer. Idempotent.
    func installShakeObserver() {
        guard shakeObserver == nil else { return }
        ShakeDetector.install()
        shakeObserver = NotificationCenter.default.addObserver(
            forName: .olafShake,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                OlafPresenter.shared.toggle()
            }
        }
    }

    func toggle() {
        isPresented ? dismiss() : present()
    }

    func present() {
        guard window == nil, let scene = Self.activeScene() else { return }

        // We present the viewer **modally** over a transparent root VC to get a bottom-to-top
        // (coverVertical) slide animation; a plain `rootViewController` assignment would be unanimated.
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let container = UIViewController()
        container.view.backgroundColor = .clear
        window.rootViewController = container
        window.makeKeyAndVisible()
        self.window = window

        let host = OlafKeyHostingController(
            rootView: OlafViewerView(onClose: { [weak self] in self?.dismiss() })
        )
        // Esc (hardware keyboard — the Mac keyboard in the simulator) closes the viewer.
        host.onEscape = { [weak self] in self?.dismiss() }
        host.modalPresentationStyle = .fullScreen
        container.present(host, animated: true)
    }

    /// - Parameter completion: Runs AFTER the window has been fully removed. Self-presenting
    ///   UIKit tools should call their `show()` here; otherwise presentation silently fails with
    ///   a "presentation in progress" error while the dismiss animation is still running.
    func dismiss(completion: (() -> Void)? = nil) {
        guard let window else { completion?(); return }
        let teardown = { [weak self] in
            self?.window?.isHidden = true
            self?.window = nil
            completion?()
        }
        // If there's a modal presentation, close it by sliding down; otherwise remove the window directly.
        if let presented = window.rootViewController?.presentedViewController {
            presented.dismiss(animated: true, completion: teardown)
        } else {
            teardown()
        }
    }

    /// Presents an embeddable SwiftUI tool modally over the Olaf window.
    /// If Olaf isn't open, opens it first so there is a context to return to.
    func presentExternal<Content: View>(rootView: Content) {
        if window == nil { present() }
        guard let root = window?.rootViewController else { return }

        var top = root
        while let presented = top.presentedViewController { top = presented }

        let host = OlafKeyHostingController(rootView: rootView)
        // Esc closes the external tool → returns to the Olaf viewer (the viewer's own Esc closes it).
        host.onEscape = { [weak host] in host?.dismiss(animated: true) }
        host.modalPresentationStyle = .fullScreen
        top.present(host, animated: true)
    }

    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

/// Hosting controller with Esc (hardware keyboard — the developer's Mac keyboard in the
/// simulator) close support. Since `keyCommands` is collected from the responder chain, it
/// doesn't require SwiftUI focus; it works as long as the Olaf window is key.
@MainActor
private final class OlafKeyHostingController<Content: View>: UIHostingController<Content> {

    var onEscape: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(
            input: UIKeyCommand.inputEscape,
            modifierFlags: [],
            action: #selector(handleEscape)
        )
        // Don't let system behaviors (e.g. the focus system) swallow Esc.
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }

    @objc private func handleEscape() {
        onEscape?()
    }
}
#endif

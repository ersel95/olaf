#if canImport(UIKit)
import UIKit
import SwiftUI

/// Viewer'ı uygulamanın kendi navigation/coordinator yapısına dokunmadan, **ayrı bir
/// `UIWindow`** içinde sunar. Böylece her projede çakışmasız çalışır.
@MainActor
final class LogFoxPresenter {

    static let shared = LogFoxPresenter()

    private var window: UIWindow?
    private var shakeObserver: NSObjectProtocol?

    private init() {}

    var isPresented: Bool { window != nil }

    /// Sallama → aç/kapat gözlemcisini kurar. İdempotent.
    func installShakeObserver() {
        guard shakeObserver == nil else { return }
        shakeObserver = NotificationCenter.default.addObserver(
            forName: .logFoxShake,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                LogFoxPresenter.shared.toggle()
            }
        }
    }

    func toggle() {
        isPresented ? dismiss() : present()
    }

    func present() {
        guard window == nil, let scene = Self.activeScene() else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(
            rootView: LogFoxViewerView(onClose: { [weak self] in self?.dismiss() })
        )
        window.makeKeyAndVisible()
        self.window = window
    }

    func dismiss() {
        window?.isHidden = true
        window = nil
    }

    /// Gömülebilir SwiftUI aracını LogFox penceresi üzerinde modal olarak sunar.
    /// LogFox açık değilse önce açar, böylece geri dönülecek bir bağlam olur.
    func presentExternal<Content: View>(rootView: Content) {
        if window == nil { present() }
        guard let root = window?.rootViewController else { return }

        var top = root
        while let presented = top.presentedViewController { top = presented }

        let host = UIHostingController(rootView: rootView)
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
#endif

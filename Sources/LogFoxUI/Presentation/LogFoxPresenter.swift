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
        ShakeDetector.install()
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

        // Saydam bir kök VC üzerinde viewer'ı **modal** sunarak alttan yukarı (coverVertical)
        // kayma animasyonu elde ediyoruz; düz `rootViewController` ataması animasyonsuz olurdu.
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let container = UIViewController()
        container.view.backgroundColor = .clear
        window.rootViewController = container
        window.makeKeyAndVisible()
        self.window = window

        let host = UIHostingController(
            rootView: LogFoxViewerView(onClose: { [weak self] in self?.dismiss() })
        )
        host.modalPresentationStyle = .fullScreen
        container.present(host, animated: true)
    }

    /// - Parameter completion: Pencere tamamen kaldırıldıktan SONRA çalışır. Kendini sunan UIKit
    ///   araçları `show()`'u burada çağırmalı; aksi halde dismiss animasyonu sürerken sunum
    ///   "presentation in progress" hatasıyla sessizce başarısız olur.
    func dismiss(completion: (() -> Void)? = nil) {
        guard let window else { completion?(); return }
        let teardown = { [weak self] in
            self?.window?.isHidden = true
            self?.window = nil
            completion?()
        }
        // Modal sunum varsa aşağı kayarak kapansın; yoksa pencereyi doğrudan kaldır.
        if let presented = window.rootViewController?.presentedViewController {
            presented.dismiss(animated: true, completion: teardown)
        } else {
            teardown()
        }
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

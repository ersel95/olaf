#if canImport(UIKit)
import UIKit
import SwiftUI

/// Viewer'ı uygulamanın kendi navigation/coordinator yapısına dokunmadan, **ayrı bir
/// `UIWindow`** içinde sunar. Böylece her projede çakışmasız çalışır.
@MainActor
final class OlafPresenter {

    static let shared = OlafPresenter()

    private var window: UIWindow?
    private var shakeObserver: NSObjectProtocol?

    private init() {}

    var isPresented: Bool { window != nil }

    /// Sallama → aç/kapat gözlemcisini kurar. İdempotent.
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

        // Saydam bir kök VC üzerinde viewer'ı **modal** sunarak alttan yukarı (coverVertical)
        // kayma animasyonu elde ediyoruz; düz `rootViewController` ataması animasyonsuz olurdu.
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
        // Esc (donanım klavyesi — simülatörde Mac klavyesi) viewer'ı kapatır.
        host.onEscape = { [weak self] in self?.dismiss() }
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

    /// Gömülebilir SwiftUI aracını Olaf penceresi üzerinde modal olarak sunar.
    /// Olaf açık değilse önce açar, böylece geri dönülecek bir bağlam olur.
    func presentExternal<Content: View>(rootView: Content) {
        if window == nil { present() }
        guard let root = window?.rootViewController else { return }

        var top = root
        while let presented = top.presentedViewController { top = presented }

        let host = OlafKeyHostingController(rootView: rootView)
        // Esc dış aracı kapatır → Olaf viewer'a geri dönülür (viewer'ın kendi Esc'i onu kapatır).
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

/// Esc (donanım klavyesi — simülatörde geliştiricinin Mac klavyesi) ile kapatma destekli
/// hosting controller. `keyCommands` responder zincirinden toplandığı için SwiftUI focus
/// gerektirmez; Olaf penceresi key olduğu sürece çalışır.
@MainActor
private final class OlafKeyHostingController<Content: View>: UIHostingController<Content> {

    var onEscape: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(
            input: UIKeyCommand.inputEscape,
            modifierFlags: [],
            action: #selector(handleEscape)
        )
        // Sistem davranışları (örn. focus sistemi) Esc'i yutmasın.
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }

    @objc private func handleEscape() {
        onEscape?()
    }
}
#endif

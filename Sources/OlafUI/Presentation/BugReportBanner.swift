#if canImport(UIKit)
import UIKit
import SwiftUI
import OlafCore
import OlafUpload

/// Bug-reporter UI orkestratörü: screenshot algılandığında **ayrı bir `UIWindow`** içinde
/// (app içeriğine dokunmadan) **alttan** Olaf ikonu + balon gösterir; **Evet** → rapor sheet'i
/// present eder; başarıda "Gönderildi" toast'ı gösterir.
///
/// `OlafPresenter` (viewer) ile aynı ayrı-pencere pattern'i izler; ondan bağımsız çalışır,
/// shake → viewer akışını etkilemez.
@MainActor
final class BugReportBanner {

    static let shared = BugReportBanner()

    private var window: UIWindow?
    private var screenshotObserver: NSObjectProtocol?
    private var autoDismissTask: Task<Void, Never>?
    private var pendingScreenshot: UIImage?

    /// Banner birkaç saniye etkileşimsiz kalırsa otomatik kaybolur.
    private let autoDismissAfter: TimeInterval = 6

    private init() {}

    // MARK: - Kurulum (OlafUpload.configure tetikler)

    /// Screenshot detector + observer'ı kurar. **Yalnız bug-reporter opt-in açıkken** çağrılır.
    /// İdempotent.
    func install() {
        guard screenshotObserver == nil else { return }
        ScreenshotDetector.shared.install()
        // Pil izleme + ağ monitörünü erkenden başlat ki ilk raporda telemetri dolu gelsin.
        OlafTelemetry.prepare()
        screenshotObserver = NotificationCenter.default.addObserver(
            forName: .olafScreenshotCaptured,
            object: nil,
            queue: .main
        ) { note in
            let image = note.object as? UIImage
            MainActor.assumeIsolated {
                BugReportBanner.shared.handleScreenshot(image)
            }
        }
    }

    // MARK: - Akış

    private func handleScreenshot(_ image: UIImage?) {
        // Gate 2: server-side kill-switch. captureEnabled değilse banner gösterme.
        guard OlafUpload.bugReportService?.isCaptureEnabled == true else { return }
        // Zaten bir banner/sheet görünüyorsa tekrarlama.
        guard window == nil else { return }
        pendingScreenshot = image
        presentBanner()
    }

    private func presentBanner() {
        guard let scene = Self.activeScene() else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let container = PassthroughViewController()
        container.view.backgroundColor = .clear
        window.rootViewController = container
        window.makeKeyAndVisible()
        self.window = window

        let host = UIHostingController(
            rootView: BugReportBannerView(
                onYes: { [weak self] in self?.presentSheet() },
                onNo: { [weak self] in self?.dismissBanner() }
            )
        )
        host.view.backgroundColor = .clear
        container.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor)
        ])
        host.didMove(toParent: container)
        container.passthroughHost = host.view

        scheduleAutoDismiss()
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.autoDismissAfter ?? 6) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    private func dismissBanner() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        window?.isHidden = true
        window = nil
    }

    private func presentSheet() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        guard let container = window?.rootViewController else { return }

        let screenshot = pendingScreenshot
        let host = UIHostingController(
            rootView: BugReportSheet(
                screenshot: screenshot,
                onClose: { [weak self] didSend in
                    self?.window?.rootViewController?.dismiss(animated: true) {
                        self?.dismissBanner()
                        if didSend {
                            BugReportToast.show("Gönderildi")
                        }
                    }
                }
            )
        )
        host.modalPresentationStyle = .formSheet
        // Banner görünümünü gizleyip tüm pencereyi sheet için kullan.
        if let passthrough = container as? PassthroughViewController {
            passthrough.passthroughHost?.isHidden = true
            passthrough.passthroughHost = nil
        }
        container.present(host, animated: true)
    }

    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

// MARK: - Passthrough container

/// Banner görünürken yalnız banner alanına dokunuşları yakalar; geri kalan dokunuşlar alttaki
/// uygulamaya geçer (modal sheet present edilene kadar app etkileşilebilir kalır).
@MainActor
private final class PassthroughViewController: UIViewController {
    weak var passthroughHost: UIView?

    override func loadView() {
        view = PassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        (view as? PassthroughView)?.hitTestProvider = { [weak self] point, event, defaultResult in
            guard let self else { return defaultResult() }
            // Modal sunum varsa (sheet açık): normal hit-test (tüm pencere etkileşilebilir).
            guard self.presentedViewController == nil else { return defaultResult() }
            // Banner görünümü yoksa: dokunuşları alttaki uygulamaya geçir.
            guard let host = self.passthroughHost else { return nil }
            // Yalnız banner alt-görünümlerine isabet eden dokunuşları yakala; gerisi app'e geçer.
            let converted = host.convert(point, from: self.view)
            return host.point(inside: converted, with: event) ? defaultResult() : nil
        }
    }
}

/// Banner görünür olduğu sürece, banner dışındaki dokunuşları alttaki uygulamaya geçiren view.
@MainActor
private final class PassthroughView: UIView {
    /// `(point, event, defaultHitTest)` → seçilen view. `defaultHitTest` super.hitTest sonucudur.
    var hitTestProvider: ((CGPoint, UIEvent?, () -> UIView?) -> UIView?)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let defaultResult = { super.hitTest(point, with: event) }
        if let provider = hitTestProvider {
            return provider(point, event, defaultResult)
        }
        return defaultResult()
    }
}

// MARK: - Banner görünümü (SwiftUI)

/// Alttan giren Olaf ikonu + balon. [Evet] [Hayır].
@MainActor
private struct BugReportBannerView: View {

    let onYes: () -> Void
    let onNo: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 12) {
                logo
                bubble
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .offset(y: appeared ? 0 : 140)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private var logo: some View {
        Image("OlafLogo", bundle: .module)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 44, height: 44)
            .foregroundColor(.white)
            .padding(10)
            .background(Circle().fill(Color.accentColor))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bir sorun mu tespit edildi? Paylaşmak ister misin?")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(action: onYes) {
                    Text("Evet")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                Button(action: onNo) {
                    Text("Hayır")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        )
    }
}
#endif

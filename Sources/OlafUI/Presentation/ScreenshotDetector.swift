#if canImport(UIKit)
import UIKit
import OlafCore

public extension Notification.Name {
    /// Kullanıcı ekran görüntüsü aldığında — render edilmiş görüntü `object` (UIImage) olarak.
    static let olafScreenshotCaptured = Notification.Name("com.olaf.screenshotCaptured")
}

/// Ekran görüntüsü algılama. Sistem screenshot görüntüsünü app'e VERMEZ; bu yüzden bildirim
/// gelince key window'u kendimiz `UIGraphicsImageRenderer` + `drawHierarchy` ile render ederiz.
///
/// Render `afterScreenUpdates: true` ile yapılır → secure (gizli) text field'ların sistem
/// maskesi etkili olur ve hassas içerik görüntüye SIZMAZ (boş/siyah çıkar). Yine de görüntü,
/// ekrandaki diğer tüm görünür bilgiyi içerir; bilgilendirilmiş onay sheet'te gösterilir.
/// (Shake için `ShakeDetector` swizzle pattern'inin notification-tabanlı eşdeğeri.)
@MainActor
final class ScreenshotDetector {

    static let shared = ScreenshotDetector()

    private var observer: NSObjectProtocol?
    private init() {}

    var isInstalled: Bool { observer != nil }

    /// `userDidTakeScreenshotNotification` gözlemcisini kurar. İdempotent.
    func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                ScreenshotDetector.shared.handleScreenshot()
            }
        }
    }

    /// Gözlemciyi kaldırır.
    func uninstall() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    private func handleScreenshot() {
        // Navigation/log timeline'ına ekran görüntüsü olayını da işle.
        Olaf.log(.info, "Ekran görüntüsü alındı", category: .screenshot)

        let image = Self.renderKeyWindow()
        NotificationCenter.default.post(name: .olafScreenshotCaptured, object: image)
    }

    /// Key window'u (Olaf'ın kendi alert pencereleri hariç) görüntüye render eder.
    static func renderKeyWindow() -> UIImage? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)
            // Olaf'ın kendi üst-katman pencerelerini (banner/viewer) hariç tut.
            .filter { $0.windowLevel < UIWindow.Level.alert }

        guard let window = windows.first(where: \.isKeyWindow)
            ?? windows.max(by: { $0.windowLevel < $1.windowLevel }) else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { _ in
            // afterScreenUpdates:true → secure text field maskesinin (ve son layout'un)
            // render'a yansıması için gerekli; aksi halde gizli alanlar görüntüye sızabilir.
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}
#endif

#if canImport(UIKit)
import UIKit

/// `UIActivityViewController`'ı en üstteki view controller'dan **doğrudan sunar**.
///
/// Not: `UIActivityViewController` bir SwiftUI `.sheet` içine `UIViewControllerRepresentable`
/// olarak gömülürse boş/beyaz ekran çıkar (child VC olarak çalışmaz, sunulması gerekir).
/// Bu yüzden UIKit ile doğrudan present ediyoruz.
@MainActor
func presentShareSheet(_ items: [Any]) {
    guard !items.isEmpty, let presenter = topViewController() else { return }

    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    // iPad: popover anchor (sourceView olmazsa çöker).
    if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
    presenter.present(controller, animated: true)
}

/// Görünür en üstteki view controller (Olaf kendi penceresinde olduğundan onu da kapsar).
@MainActor
private func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
    let window = windows.first(where: \.isKeyWindow)
        ?? windows.max(by: { $0.windowLevel < $1.windowLevel })

    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
        top = presented
    }
    return top
}
#endif

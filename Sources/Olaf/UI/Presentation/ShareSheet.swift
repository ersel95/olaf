#if canImport(UIKit)
import UIKit

/// Presents `UIActivityViewController` **directly** from the topmost view controller.
///
/// Note: if `UIActivityViewController` is embedded in a SwiftUI `.sheet` as a
/// `UIViewControllerRepresentable`, it produces a blank/white screen (it doesn't work as a child
/// VC, it must be presented). That's why we present it directly via UIKit.
@MainActor
func presentShareSheet(_ items: [Any]) {
    guard !items.isEmpty, let presenter = topViewController() else { return }

    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    // iPad: popover anchor (crashes without a sourceView).
    if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
    presenter.present(controller, animated: true)
}

/// The visible topmost view controller (also covers Olaf's own window since it has one).
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

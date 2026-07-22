import Foundation
import SwiftUI

/// General-purpose facade for OlafUI: shake → viewer setup, external tool registration, presentation.
///
/// ```swift
/// Olaf.start(.default)
/// OlafUI.install()       // viewer (shake) setup
/// ```
///
/// If you want to add your own custom diagnostic tool, use `install(tools:)` or `register(_:)`.
public enum OlafUI {

    /// Installs the observer that opens the viewer when the device is shaken, and registers the
    /// given external tools. Idempotent; call once.
    /// - Parameter tools: Custom external tool bridges the host wants to add.
    @MainActor
    public static func install(tools: [any ExternalToolBridge] = []) {
        #if canImport(UIKit)
        OlafPresenter.shared.installShakeObserver()
        #endif
        for tool in tools {
            ExternalToolRegistry.shared.register(tool)
        }
    }

    /// Registers a single custom external tool bridge. Becomes a switch-to button in the viewer.
    public static func register(_ bridge: any ExternalToolBridge) {
        ExternalToolRegistry.shared.register(bridge)
    }

    /// Removes all registered external tools.
    public static func unregisterAllTools() {
        ExternalToolRegistry.shared.removeAll()
    }

    /// Registers a handler for taps on the Olaf logo in the viewer's navigation bar.
    ///
    /// When a handler is set, the logo becomes a button: tapping it closes the viewer and invokes
    /// the handler **after** the viewer has fully closed, so it is safe to present another
    /// diagnostics tool from the handler. Useful when Olaf is installed alongside another
    /// shake-activated tool: shake opens Olaf first, and the logo hands off to the other tool.
    /// Pass `nil` to remove the handler (the logo becomes a plain image again).
    @MainActor
    public static func onLogoTap(_ handler: (() -> Void)?) {
        #if canImport(UIKit)
        OlafPresenter.shared.logoTapHandler = handler
        #endif
    }

    /// Opens the viewer programmatically.
    @MainActor
    public static func present() {
        #if canImport(UIKit)
        OlafPresenter.shared.present()
        #endif
    }

    /// Closes the viewer programmatically.
    /// - Parameter completion: Runs AFTER the viewer has fully closed. Self-presenting UIKit
    ///   tools should call their `show()` here (presenting before the dismiss animation finishes fails).
    @MainActor
    public static func dismiss(completion: (() -> Void)? = nil) {
        #if canImport(UIKit)
        OlafPresenter.shared.dismiss(completion: completion)
        #else
        completion?()
        #endif
    }

    /// Presents an embeddable SwiftUI tool modally over Olaf's own window.
    /// Returns to the Olaf viewer when dismissed.
    ///
    /// Self-presenting UIKit tools should use `dismiss()` + their own `show()` instead.
    @MainActor
    public static func presentExternal<Content: View>(@ViewBuilder _ content: () -> Content) {
        #if canImport(UIKit)
        OlafPresenter.shared.presentExternal(rootView: content())
        #endif
    }
}

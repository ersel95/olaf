import Foundation
import SwiftUI
import OlafCore

/// OlafUI'ın genel cephesi: shake → viewer kurulumu, dış araç kaydı, sunum.
///
/// ```swift
/// Olaf.start(.bankingDefault)
/// OlafUI.install()       // viewer (shake) kurulumu
/// ```
///
/// Kendi özel tanılama aracını eklemek istersen `install(tools:)` veya `register(_:)` kullanabilirsin.
public enum OlafUI {

    /// Cihaz sallandığında viewer'ı açacak gözlemciyi kurar ve verilen dış araçları kaydeder.
    /// İdempotent; bir kez çağırın.
    /// - Parameter tools: Host'un eklemek istediği özel dış araç köprüleri.
    @MainActor
    public static func install(tools: [any ExternalToolBridge] = []) {
        #if canImport(UIKit)
        OlafPresenter.shared.installShakeObserver()
        #endif
        for tool in tools {
            ExternalToolRegistry.shared.register(tool)
        }
    }

    /// Tek bir özel dış araç köprüsü kaydeder. Viewer'da geçiş butonu olur.
    public static func register(_ bridge: any ExternalToolBridge) {
        ExternalToolRegistry.shared.register(bridge)
    }

    /// Kayıtlı tüm dış araçları kaldırır.
    public static func unregisterAllTools() {
        ExternalToolRegistry.shared.removeAll()
    }

    /// Viewer'ı programatik aç.
    @MainActor
    public static func present() {
        #if canImport(UIKit)
        OlafPresenter.shared.present()
        #endif
    }

    /// Viewer'ı programatik kapat.
    /// - Parameter completion: Viewer tamamen kapandıktan SONRA çalışır. Kendini sunan UIKit
    ///   araçları `show()`'u burada çağırmalı (dismiss animasyonu bitmeden sunum başarısız olur).
    @MainActor
    public static func dismiss(completion: (() -> Void)? = nil) {
        #if canImport(UIKit)
        OlafPresenter.shared.dismiss(completion: completion)
        #else
        completion?()
        #endif
    }

    /// Gömülebilir bir SwiftUI aracını Olaf'un kendi penceresi üzerinde modal olarak sunar.
    /// Kapanınca Olaf viewer'a geri dönülür.
    ///
    /// Kendini sunan UIKit araçları bunun yerine `dismiss()` + kendi `show()`'unu kullanmalıdır.
    @MainActor
    public static func presentExternal<Content: View>(@ViewBuilder _ content: () -> Content) {
        #if canImport(UIKit)
        OlafPresenter.shared.presentExternal(rootView: content())
        #endif
    }
}

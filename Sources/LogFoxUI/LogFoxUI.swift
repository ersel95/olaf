import Foundation
import SwiftUI
import LogFoxCore

/// LogFoxUI'ın genel cephesi: shake → viewer kurulumu, dış araç (Netfox) kaydı, sunum.
///
/// Netfox köprüsü ayrı bir ürün/modüldedir (**LogFoxNetfox**). Tüketici bu ürünü target'a ekleyip
/// init'te `LogFoxNetfox.install()` çağırınca köprü buraya kaydedilir ve viewer'da "Netfox" butonu çıkar.
///
/// ```swift
/// LogFox.start(.bankingDefault)
/// LogFoxUI.install()       // viewer (shake) kurulumu
/// LogFoxNetfox.install()   // LogFoxNetfox ürünü eklendiyse: Netfox butonunu ekler
/// ```
///
/// Kendi özel aracını eklemek istersen `install(tools:)` veya `register(_:)` kullanabilirsin.
public enum LogFoxUI {

    /// Cihaz sallandığında viewer'ı açacak gözlemciyi kurar ve verilen dış araçları kaydeder.
    /// İdempotent; bir kez çağırın.
    /// - Parameter tools: Host'un eklemek istediği özel dış araç köprüleri. (Netfox için ayrı
    ///   `LogFoxNetfox` ürünü + `LogFoxNetfox.install()` kullanın.)
    @MainActor
    public static func install(tools: [any ExternalToolBridge] = []) {
        #if canImport(UIKit)
        LogFoxPresenter.shared.installShakeObserver()
        #endif
        for tool in tools {
            ExternalToolRegistry.shared.register(tool)
        }
    }

    /// Tek bir özel dış araç köprüsü kaydeder. Viewer'da geçiş butonu olur. (Netfox için `LogFoxNetfox`.)
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
        LogFoxPresenter.shared.present()
        #endif
    }

    /// Viewer'ı programatik kapat.
    @MainActor
    public static func dismiss() {
        #if canImport(UIKit)
        LogFoxPresenter.shared.dismiss()
        #endif
    }

    /// Gömülebilir bir SwiftUI aracını LogFox'un kendi penceresi üzerinde modal olarak sunar.
    /// Kapanınca LogFox viewer'a geri dönülür.
    ///
    /// Netfox gibi kendini sunan UIKit araçları bunun yerine `dismiss()` + kendi `show()`'unu kullanmalıdır.
    @MainActor
    public static func presentExternal<Content: View>(@ViewBuilder _ content: () -> Content) {
        #if canImport(UIKit)
        LogFoxPresenter.shared.presentExternal(rootView: content())
        #endif
    }
}

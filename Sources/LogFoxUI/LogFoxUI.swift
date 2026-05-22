import Foundation
import SwiftUI
import LogFoxCore

/// LogFoxUI'ın genel cephesi: shake → viewer kurulumu, dış araç (Netfox / Pulse) kaydı, sunum.
///
/// Dış araçlar **host app tarafında** belirlenir ve init'te gönderilir. `#if canImport(...)`
/// kontrolleri host'ta yapılmalıdır (Netfox/Pulse modülleri orada link'lenir; bu paket onlara
/// bağlı değildir → paket içinde `canImport` her zaman `false` döner).
///
/// ```swift
/// LogFox.start(.bankingDefault)
///
/// var tools: [any ExternalToolBridge] = []
/// #if canImport(netfox)
/// if config.enableNetfox { tools.append(NetfoxBridge()) }
/// #endif
/// #if canImport(PulseUI)
/// if config.enablePulse { tools.append(PulseBridge()) }
/// #endif
///
/// LogFoxUI.install(tools: tools)   // karar init'te gönderilir
/// ```
public enum LogFoxUI {

    /// Cihaz sallandığında viewer'ı açacak gözlemciyi kurar ve verilen dış araçları kaydeder.
    /// İdempotent; bir kez çağırın.
    /// - Parameter tools: Host'un etkinleştirmeye karar verdiği geçiş köprüleri (Netfox, Pulse...).
    @MainActor
    public static func install(tools: [any ExternalToolBridge] = []) {
        #if canImport(UIKit)
        LogFoxPresenter.shared.installShakeObserver()
        #endif
        for tool in tools {
            ExternalToolRegistry.shared.register(tool)
        }
    }

    /// Tek bir dış araç köprüsü kaydeder (örn. Netfox/Pulse). Viewer'da geçiş butonu olur.
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

    /// Gömülebilir bir SwiftUI aracını (örn. Pulse `ConsoleView`) LogFox'un kendi penceresi
    /// üzerinde modal olarak sunar. Kapanınca LogFox viewer'a geri dönülür.
    ///
    /// Netfox gibi kendini sunan UIKit araçları bunun yerine `dismiss()` + kendi `show()`'unu
    /// kullanmalıdır.
    @MainActor
    public static func presentExternal<Content: View>(@ViewBuilder _ content: () -> Content) {
        #if canImport(UIKit)
        LogFoxPresenter.shared.presentExternal(rootView: content())
        #endif
    }
}

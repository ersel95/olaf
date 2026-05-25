import Foundation
import LogFoxUI

/// LogFox ↔ Netfox köprü ürünü.
///
/// Bu ürünü (`LogFoxNetfox`) hedefinize eklediğinizde netfox linklenir. Köprünün LogFox viewer'ında
/// "Netfox" butonu olarak görünmesi için init sırasında **bir kez** `LogFoxNetfox.install()` çağırın:
///
/// ```swift
/// LogFox.start(.bankingDefault)
/// LogFoxUI.install()        // viewer
/// LogFoxNetfox.install()    // Netfox butonu
/// ```
///
/// (Swift'te bir modül linklenince kendi kodunu otomatik çalıştıramaz; bu yüzden tek satırlık
/// `install()` çağrısı gerekir. `canImport(UIKit)` olmayan platformlarda no-op'tur.)
public enum LogFoxNetfox {

    /// Netfox köprüsünü LogFox viewer'ına kaydeder. İdempotent değildir; bir kez çağırın.
    @MainActor
    public static func install() {
        #if canImport(UIKit)
        LogFoxUI.register(NetfoxBridge())
        #endif
    }
}

#if canImport(UIKit)
import netfox

/// Netfox network logger'a geçiş köprüsü.
struct NetfoxBridge: ExternalToolBridge {
    let title = "Netfox"
    var systemImage: String? { "network" }

    @MainActor func open() {
        LogFoxUI.dismiss()          // önce LogFox'u kapat
        NFX.sharedInstance().show() // Netfox kendi penceresinde açılır
    }
}
#endif

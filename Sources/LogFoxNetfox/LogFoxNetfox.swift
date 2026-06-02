import Foundation
import LogFoxUI

/// LogFox ↔ Netfox köprü ürünü. Host'un netfox'u doğrudan import etmesi gerekmez.
public enum LogFoxNetfox {

    /// Netfox'u başlatır ve shake jestini LogFox'a bırakır. İdempotent; `canImport(UIKit)` yoksa no-op.
    public static func startCapture() {
        #if canImport(UIKit)
        NFX.sharedInstance().start()
        NFX.sharedInstance().setGesture(.custom)
        #endif
    }

    /// `LogFoxNetwork.install(chainingTo:)`'a verilecek Netfox URLProtocol'ü — LogFox proxy'sine zincirlenir.
    public static var chainProtocolClasses: [AnyClass] {
        #if canImport(UIKit)
        return [NFXProtocol.self]
        #else
        return []
        #endif
    }

    /// Netfox köprüsünü viewer'a kaydeder (toolbar'da "Netfox" butonu). Bir kez çağırın.
    @MainActor
    public static func install() {
        #if canImport(UIKit)
        LogFoxUI.register(NetfoxBridge())
        #endif
    }
}

#if canImport(UIKit)
import netfox

struct NetfoxBridge: ExternalToolBridge {
    let title = "Netfox"
    var systemImage: String? { "network" }

    @MainActor func open() {
        // LogFox penceresi tamamen kapandıktan SONRA Netfox'u sun; aksi halde dismiss
        // animasyonu sürerken sunum "presentation in progress" ile sessizce başarısız olur.
        LogFoxUI.dismiss {
            NFX.sharedInstance().show()
        }
    }
}
#endif

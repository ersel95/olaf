# LogFox — Entegrasyon Rehberi

LogFox'u uygulamaya bağlamak için rehber. **Netfox** geçişi opsiyonel `LogFoxNetfox` ürünüyle gelir.

> **Tasarım ilkesi:** Çekirdek (LogFoxCore/UI) hiçbir dış araca bağlı değildir. Netfox entegrasyonu
> **ayrı bir ürün** (`LogFoxNetfox`) ile izole edilmiştir — host bunu seçtiğinde netfox linklenir; host
> doğrudan `import netfox` yapmaz. Başka araçlar (örn. Pulse) jenerik `ExternalToolBridge` ile host'ta eklenebilir.
> Hızlı yol: tek-dosya template [`Integration/LogFoxIntegration.swift`](Integration/LogFoxIntegration.swift)
> ve makine-takipli [`AGENTS.md`](AGENTS.md).

> **Gating notu:** TestFlight build'i genelde UAT/Prod config'tedir; `#if DEBUG` yalnız Test config'te tanımlıdır.
> LogFox'u `#if DEBUG`'a bağlama — `#if !PROD` derleme sınırı (önerilen, capture kodu prod binary'sine girmez)
> veya runtime feature flag kullan.

---

## 1. Paketi ekle

Xcode → Add Packages → `https://github.com/ersel95/logfox` → ana app target'ına ("Choose Package Products"):
- `LogFoxCore` (motor) + `LogFoxUI` (viewer) — zorunlu
- `LogFoxNetwork` — network loglarını LogFox'ta görmek için (§4)
- `LogFoxNetfox` — Netfox geçişi için (§3)

(App extension'lara yalnız `LogFoxCore`.)

## 2. Entegrasyon dosyasını kopyala

[`Integration/LogFoxIntegration.swift`](Integration/LogFoxIntegration.swift) dosyasını host app'e (örn. `Core/Utils/`)
kopyalayın. İçinde `LogFoxManager` (başlatma + loglama) ve `LogFoxNetworkLogger` enum'u hazırdır.
**Köprü tanımı içermez** — Netfox köprüsü pakettedir. `// ADAPT:` satırlarını uyarlayın.

```swift
@_exported import LogFoxCore
import LogFoxUI
#if canImport(LogFoxNetwork)
import LogFoxNetwork
#endif
#if canImport(LogFoxNetfox)
import LogFoxNetfox
#endif

public enum LogFoxNetworkLogger { case netfox, none }

public final class LogFoxManager {
    public static let shared = LogFoxManager()
    private init() {}
    private var activeNetwork: LogFoxNetworkLogger = .none

    public func initialize(network: LogFoxNetworkLogger = .none) {
        #if !PROD
        activeNetwork = network
        LogFox.start(.bankingDefault)
        #if canImport(LogFoxNetwork)
        LogFoxNetwork.startAutomaticCapture()
        #endif
        if network == .netfox {
            #if canImport(LogFoxNetfox)
            LogFoxNetfox.startCapture()      // NFX.start + shake'i LogFox'a bırak
            #endif
        }
        Task { @MainActor in
            LogFoxUI.install()
            if network == .netfox {
                #if canImport(LogFoxNetfox)
                LogFoxNetfox.install()       // viewer'da "Netfox" butonu
                #endif
            }
        }
        #endif
    }
}
```

## 3. Başlatmayı bağla

App giriş noktanızda — **paylaşılan URLSession kurulmadan ÖNCE** (SwiftUI `App.init` veya
`AppDelegate.didFinishLaunching` başı, session preload'undan önce):
```swift
LogFoxManager.shared.initialize(network: .netfox)   // .netfox / .none
```
`LogFoxNetfox.startCapture()` Netfox'u başlatır ve shake'ini otomatik kapatır (`NFX.setGesture(.custom)`) →
shake artık LogFox'a aittir, içeriden Netfox'a geçilir. Host'un ayrıca `NFX.start()` çağırmasına gerek yoktur.

## 4. Network loglarını LogFox'ta listelemek — `LogFoxNetwork`

İstek/yanıtları `.network` kategorisinde, **BankingRedactor'dan geçirerek** (PAN/IBAN/token maskeli) loglar.

### ÖNERİLEN: tek satır otomatik capture (networking koduna dokunmadan)
`startAutomaticCapture()`, `URLSessionConfiguration`'ı swizzle ederek tüm session'lara (Alamofire dahil)
protokolü enjekte eder; proxy session sunucu trust'ını kabul eder → **SSL/sertifika kırılmaz**. `initialize` içinde hazır:
```swift
LogFoxNetwork.startAutomaticCapture()                                // gövde+header default açık
LogFoxNetwork.startAutomaticCapture(LogFoxNetworkConfiguration(
    capturesBodies: false,
    includedURLs: ["api-gateway"],                                   // boş = tümü
    excludedURLs: ["firebaseio", "crashlytics", "googleapis"]        // SDK gürültüsünü gizle (öncelikli)
))
```

### Kendi özel session'ınız varsa: deterministik enjeksiyon + Netfox zinciri
Host kendi `URLSessionConfiguration`'ını kuruyorsa, otomatik swizzle yerine session kurulurken tek satır.
Bu, `.netfox` modunda LogFox'u Netfox'a **zincirler** (URLProtocol "ilk eşleşen kazanır" → LogFox yakalar,
proxy'sinden Netfox'a geçirir → ikisi de görür):
```swift
// LogFoxManager içindeki configureNetworkCapture(_:) yardımcısı:
LogFoxManager.shared.configureNetworkCapture(configuration)
// (içeride: LogFoxNetwork.install(into: configuration, chainingTo: LogFoxNetfox.chainProtocolClasses))
```
Bunu kullanıyorsanız `startAutomaticCapture`'a gerek kalmaz.

> **Güvenlik:** Gövde/header default açıktır → tüm trafik loglanır (BankingRedactor maskeler ama keyfi JSON'daki
> her PII garanti değil). Trust kabulü ve gövde loglama **yalnız non-prod debug** içindir → PROD'da çalışmamalı.

## 5. Uygulamada loglama — her zaman `LogFoxManager` üzerinden

Uygulama kodu `LogFox`'a doğrudan bağlanmaz; manager üzerinden loglar (`trace/debug/info/notice/warning/error/critical`
+ `error(Error)`; çağıran dosya/satır korunur, PROD'da no-op).
```swift
LogFoxManager.shared.warning("token decode hatası", category: .security)
LogFoxManager.shared.error(error, category: .payment, metadata: ["code": code])
```

### Kategorileri genişletme
Entegrasyon dosyasındaki `extension LogCategory` bloğuna projenizin modüllerini ekleyin:
```swift
public extension LogCategory {
    static let cards: LogCategory = "cards"
    static let transfers: LogCategory = "transfers"
}
```
Dosya `@_exported import LogFoxCore` içerir → çağrı yerleri `import LogFoxCore` yazmadan kullanabilir.

---

## Netfox dışında bir araç eklemek
Jenerik geçiş `ExternalToolBridge` ile yapılır:
```swift
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, ya da LogFoxUI.presentExternal { ... } */ }
}
LogFoxUI.register(SomeToolBridge())
```
Gömülebilir SwiftUI araçları için `LogFoxUI.presentExternal { SomeView() }`; kendini sunan UIKit araçları için
`LogFoxUI.dismiss()` + aracın kendi `show()`'u.

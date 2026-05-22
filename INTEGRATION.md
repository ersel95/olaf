# LogFox — Entegrasyon Rehberi

LogFox'u uygulamaya, **Netfox** ve **Pulse** ile uyumlu olacak şekilde bağlamak için rehber.

> **Tasarım ilkesi:** Paket Netfox/Pulse'a **bağlı değildir**. Bu araçlara geçiş host app tarafında, `#if canImport(...)` ile opsiyonel olarak kurulur. Bir projede **yalnız bir** network logger aktiftir; host hangisini kullandığını bir enum (`.netfox` / `.pulse` / `.none`) ile **init sırasında** seçer. Hızlı yol için: tek-dosya template [`Integration/LogFoxIntegration.swift`](Integration/LogFoxIntegration.swift) ve makine-takipli [`AGENTS.md`](AGENTS.md).

> **Gating notu:** TestFlight build'i genelde UAT/Prod config'tedir; `#if DEBUG` yalnız Test config'te tanımlıdır. LogFox'u `#if DEBUG`'a bağlama — **runtime feature flag** kullan. PROD davranışını siz ayarlarsınız.

---

## Neden `canImport` host tarafında?

`#if canImport(PulseUI)` derleme zamanında **modül o target'a link'liyse** doğrudur. LogFox paketi Netfox/Pulse'a bağlı olmadığından, paket içinde `canImport(PulseUI)` **her zaman `false`** döner. Bu yüzden tespit, Netfox/Pulse'ın gerçekten link'lendiği **host app**'te yapılır. Host, sonucu (etkin köprüler listesini) init'te pakete verir → "karar SPM'e init'te gönderilir".

```
Host app  ──(seçili logger: .netfox/.pulse/.none + canImport)──►  LogFoxUI.install(tools: [...])
                                                                        │
shake ──► LogFox viewer ──► [Netfox] veya [Pulse] butonu (seçilen tek araç)
```

---

## 1. Paketi ekle

Xcode → Add Packages → `https://github.com/ersel95/logfox` → ana app target'ına:
- `LogFoxCore`
- `LogFoxUI`
- `LogFoxNetwork` *(opsiyonel — network loglarını LogFox'ta görmek isterseniz, §7)*

(App extension'lara yalnız `LogFoxCore`.)

## 2. Entegrasyon dosyasını kopyala

[`Integration/LogFoxIntegration.swift`](Integration/LogFoxIntegration.swift) dosyasını host app'e (örn. `Core/Utils/`) kopyalayın. İçinde `LogFoxManager`, `LogFoxNetworkLogger` enum'u ve canImport-gate'li `NetfoxBridge` + `PulseBridge` hazırdır. `// ADAPT:` satırlarını uyarlayın.

Özet (tam içerik template dosyasında):

```swift
import LogFoxCore
import LogFoxUI
#if canImport(netfox)
import netfox
#endif
#if canImport(PulseUI)
import PulseUI
#endif

/// Projede aktif olan tek network logger.
public enum LogFoxNetworkLogger { case netfox, pulse, none }

public final class LogFoxManager {
    public static let shared = LogFoxManager()
    private init() {}

    public func initialize(networkLogger: LogFoxNetworkLogger = .none) {
        #if !PROD
        LogFox.start(.bankingDefault)
        Task { @MainActor in
            var bridges: [any ExternalToolBridge] = []
            switch networkLogger {
            case .netfox:
                #if canImport(netfox)
                bridges.append(NetfoxBridge())
                #endif
            case .pulse:
                #if canImport(PulseUI)
                bridges.append(PulseBridge())
                #endif
            case .none:
                break
            }
            LogFoxUI.install(tools: bridges)
        }
        #endif
    }
}
```

### Netfox köprüsü (kendini sunan UIKit aracı)
```swift
#if canImport(netfox)
struct NetfoxBridge: ExternalToolBridge {
    let title = "Netfox"
    var systemImage: String? { "network" }
    @MainActor func open() {
        LogFoxUI.dismiss()
        NFX.sharedInstance().show()
    }
}
#endif
```

### Pulse köprüsü (gömülebilir SwiftUI aracı)
```swift
#if canImport(PulseUI)
struct PulseBridge: ExternalToolBridge {
    let title = "Pulse"
    var systemImage: String? { "waveform.path.ecg" }
    @MainActor func open() {
        LogFoxUI.presentExternal { PulseConsoleScreen() }
    }
}

private struct PulseConsoleScreen: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ConsoleView()
                .navigationTitle("Pulse")
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Kapat") { dismiss() } } }
        }
    }
}
#endif
```

> **İki sunum modeli:** Netfox kendi penceresinde açılır → köprü `dismiss()` + `NFX.show()` yapar. Pulse gömülebilir bir SwiftUI ekranıdır → `LogFoxUI.presentExternal { ... }` ile LogFox'un kendi penceresi üzerinde modal sunulur; "Kapat" LogFox viewer'a döner.

## 3. Başlatmayı bağla

`Application/YapiKredi_AzApp.swift` (mevcut Netfox init'inin yanına):
```swift
DispatchQueue.main.async {
    NetfoxManager.shared.initialize()   // (Netfox kullanılıyorsa) içinde setGesture(.custom)
    LogFoxManager.shared.initialize(networkLogger: .netfox)   // .netfox / .pulse / .none
}
```

## 4. Netfox'u shake'ten çıkar (çakışma çözümü)

`NetfoxManager.initialize()` içinde, `NFX.sharedInstance().start()` ardına:
```swift
NFX.sharedInstance().setGesture(.custom)   // shake artık LogFox'a ait
```
Böylece **shake → LogFox açılır**; içeriden Netfox/Pulse'a geçilir. (Pulse'ın shake'i yoktur, ek işlem gerekmez.)

## 5. Developer Options toggle (opsiyonel)

`DeveloperConfigView`'a "LogFox" satırı: `LogFox.isEnabled` aç/kapat, "Logları göster" (`LogFoxUI.present()`), "Temizle" (`LogFox.clear()`), "Paylaş" (`LogFox.exportFileURL()`).

## 6. (Opsiyonel) Network loglarını LogFox'ta listelemek — `LogFoxNetwork`

LogFox kendi `URLProtocol`'ü ile istek/yanıtları yakalayıp `.network` kategorisinde, **BankingRedactor'dan
geçirerek** (PAN/IBAN/token maskeli) loglar. Böylece app + network logları tek listede görünür; Netfox/Pulse'a
geçiş butonu derin inceleme için kalır.

Yakalama parametreleri (gövde/header) **default açık** ve **init'te** verilir:

```swift
import LogFoxNetwork

// A) Custom URLSession/Alamofire config (ÖNERİLEN — BaseService'te NFXProtocol enjeksiyonunun yanına):
LogFoxNetwork.install(into: sessionConfiguration)   // default config: gövde + header açık

// İsterseniz parametreleri init'te kısın:
LogFoxNetwork.install(
    into: sessionConfiguration,
    with: LogFoxNetworkConfiguration(capturesBodies: false, capturesHeaders: true, maxBodyLength: 8000)
)

// B) veya URLSession.shared / global istekler için:
LogFoxNetwork.installGlobally()                     // veya .installGlobally(myConfig)
```

### Netfox/Pulse ile BİRLİKTE yakalama (zincirleme)

Aynı session'da iki `URLProtocol` çakışır: ilk yakalayan, isteği kendi temiz session'ında yeniden
başlatır ve diğeri trafiği göremez. İkisinin de yakalaması için LogFox'u **zincirleyin** — LogFox
yakalar, sonra isteği zincirlenen protokole (Netfox) devreder:

```swift
LogFoxNetwork.install(into: configuration, chainingTo: [NFXProtocol.self])
// Akış: istek → LogFox (yakala+redakte) → NFXProtocol (Netfox yakalar) → ağ
```

> **YapiKredi'de:** `BaseService`'te `NFXProtocol`'ün `configuration.protocolClasses`'a eklendiği yerde,
> LogFox etkinse NFX'i ana session'a koymak yerine LogFox'a zincirleyin:
> ```swift
> if !Feature.isDisabled(.logFox) {
>     LogFoxNetwork.install(into: configuration,
>         chainingTo: !Feature.isDisabled(.netfox) ? [NFXProtocol.self] : [])
> } else if !Feature.isDisabled(.netfox) {
>     configuration.protocolClasses = [NFXProtocol.self] + (configuration.protocolClasses ?? [])
> }
> ```
> Network kayıtları viewer'da `network` kategori chip'iyle görünür; Netfox switch'i de dolu kalır.
>
> **Güvenlik:** Gövde/header default açıktır → tüm trafik loglanır. Hepsi `BankingRedactor`'dan geçer
> (PAN/IBAN/token, `Authorization`/`Cookie` header'ları maskelenir), ancak keyfi JSON'daki her PII
> garanti yakalanamaz. Daha sıkı istiyorsanız `capturesBodies: false` ile init edin.

## 7. Uygulamada loglama — her zaman `LogFoxManager` üzerinden

Uygulama kodu `LogFox`'a **doğrudan bağlanmaz**; tek entegrasyon noktası olan manager üzerinden loglar.
`LogFoxManager` `trace/debug/info/notice/warning/error/critical` + `error(Error)` sağlar; çağıran dosya/satır
korunur, LogFox başlatılmamışsa (PROD) no-op'tur.

```swift
// önce:
print("⚠️ token decode hatası")
// sonra:
LogFoxManager.shared.warning("token decode hatası", category: .security)
LogFoxManager.shared.error(error, category: .payment, metadata: ["code": code])
```
Kademeli göç önerilir. Network logları BaseService'teki `LogFoxNetwork.install` ile otomatik yakalanır;
manager'a yalnız üst-seviye iş olayları girer.

### Kategorileri genişletme

`LogCategory` string-backed'tir; entegrasyon dosyasındaki `extension LogCategory` bloğuna projenizin
modüllerini ekleyin:

```swift
public extension LogCategory {
    static let cards: LogCategory = "cards"
    static let accounts: LogCategory = "accounts"
    static let transfers: LogCategory = "transfers"
}
```

Entegrasyon dosyası `@_exported import LogFoxCore` içerir → çağrı yerlerinde `import LogFoxCore` yazmadan
`LogFoxManager.shared.info("...", category: .cards)` kullanabilirsiniz. Viewer'da bu kategoriler filtre
ve kategori chip'i olarak otomatik görünür.

---

## Pulse hakkında not

Pulse'ın **network yakalaması** host'un kendi Pulse kurulumudur (`URLSessionProxyDelegate` / `Experimental.URLSessionProxy`) — LogFox kapsamı dışındadır. LogFox yalnız Pulse konsoluna **geçiş** sağlar. Pulse'ı kendi loglama backend'iniz olarak da kullanmak isterseniz, gelecekte LogFox için bir `swift-log` / Pulse köprüsü (Faz 4) eklenebilir.

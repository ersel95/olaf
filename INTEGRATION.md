# Olaf — Entegrasyon Rehberi

Olaf'u uygulamaya bağlamak için rehber.

> **Tasarım ilkesi:** Çekirdek (OlafCore/UI) hiçbir dış araca bağlı değildir. Dış tanılama araçları
> (örn. başka bir network logger) jenerik `ExternalToolBridge` ile host tarafında eklenebilir.
> Hızlı yol: tek-dosya template [`Integration/OlafIntegration.swift`](Integration/OlafIntegration.swift)
> ve makine-takipli [`AGENTS.md`](AGENTS.md).

> **Gating notu:** TestFlight build'i genelde UAT/Prod config'tedir; `#if DEBUG` yalnız Test config'te tanımlıdır.
> Olaf'u `#if DEBUG`'a bağlama — `#if !PROD` derleme sınırı (önerilen, capture kodu prod binary'sine girmez)
> veya runtime feature flag kullan.

---

## 1. Paketi ekle

Xcode → Add Packages → `https://github.com/ersel95/olaf` → ana app target'ına ("Choose Package Products"):
- `OlafCore` (motor) + `OlafUI` (viewer) — zorunlu
- `OlafNetwork` — network loglarını Olaf'ta görmek için (§4)

(App extension'lara yalnız `OlafCore`.)

## 2. Entegrasyon dosyasını kopyala

[`Integration/OlafIntegration.swift`](Integration/OlafIntegration.swift) dosyasını host app'e (örn. `Core/Utils/`)
kopyalayın. İçinde `OlafManager` (başlatma + loglama) hazırdır. `// ADAPT:` satırlarını uyarlayın.

```swift
@_exported import OlafCore
import OlafUI
#if canImport(OlafNetwork)
import OlafNetwork
#endif

public final class OlafManager {
    public static let shared = OlafManager()
    private init() {}

    public func initialize() {
        #if !PROD
        Olaf.start(.bankingDefault)
        #if canImport(OlafNetwork)
        OlafNetwork.startAutomaticCapture()
        #endif
        Task { @MainActor in
            OlafUI.install()
        }
        #endif
    }
}
```

## 3. Başlatmayı bağla

App giriş noktanızda — **paylaşılan URLSession kurulmadan ÖNCE** (SwiftUI `App.init` veya
`AppDelegate.didFinishLaunching` başı, session preload'undan önce):
```swift
OlafManager.shared.initialize()
```
Shake jesti Olaf'a aittir; cihaz sallanınca viewer açılır.

## 4. Network loglarını Olaf'ta listelemek — `OlafNetwork`

İstek/yanıtları `.network` kategorisinde, **BankingRedactor'dan geçirerek** (PAN/IBAN/token maskeli) loglar.

### ÖNERİLEN: tek satır otomatik capture (networking koduna dokunmadan)
`startAutomaticCapture()`, `URLSessionConfiguration`'ı swizzle ederek tüm session'lara (Alamofire dahil)
protokolü enjekte eder; proxy session sunucu trust'ını kabul eder → **SSL/sertifika kırılmaz**. `initialize` içinde hazır:
```swift
OlafNetwork.startAutomaticCapture()                                // gövde+header default açık
OlafNetwork.startAutomaticCapture(OlafNetworkConfiguration(
    capturesBodies: false,
    includedURLs: ["api-gateway"],                                   // boş = tümü
    excludedURLs: ["firebaseio", "crashlytics", "googleapis"]        // SDK gürültüsünü gizle (öncelikli)
))
```

### Kendi özel session'ınız varsa: deterministik enjeksiyon
Host kendi `URLSessionConfiguration`'ını kuruyorsa, otomatik swizzle yerine session kurulurken tek satır:
```swift
// OlafManager içindeki configureNetworkCapture(_:) yardımcısı:
OlafManager.shared.configureNetworkCapture(configuration)
// (içeride: OlafNetwork.install(into: configuration))
```
Bunu kullanıyorsanız `startAutomaticCapture`'a gerek kalmaz. Başka bir capture aracının URLProtocol'ünü
aynı trafiğe zincirlemek için `OlafNetwork.install(into:chainingTo:)` kullanılabilir.

> **Güvenlik:** Gövde/header default açıktır → tüm trafik loglanır (BankingRedactor maskeler ama keyfi JSON'daki
> her PII garanti değil). Trust kabulü ve gövde loglama **yalnız non-prod debug** içindir → PROD'da çalışmamalı.

## 5. Uygulamada loglama — her zaman `OlafManager` üzerinden

Uygulama kodu `Olaf`'a doğrudan bağlanmaz; manager üzerinden loglar (`trace/debug/info/notice/warning/error/critical`
+ `error(Error)`; çağıran dosya/satır korunur, PROD'da no-op).
```swift
OlafManager.shared.warning("token decode hatası", category: .security)
OlafManager.shared.error(error, category: .payment, metadata: ["code": code])
```

### Kategorileri genişletme
Entegrasyon dosyasındaki `extension LogCategory` bloğuna projenizin modüllerini ekleyin:
```swift
public extension LogCategory {
    static let cards: LogCategory = "cards"
    static let transfers: LogCategory = "transfers"
}
```
Dosya `@_exported import OlafCore` içerir → çağrı yerleri `import OlafCore` yazmadan kullanabilir.

---

## Dış bir tanılama aracı eklemek
Jenerik geçiş `ExternalToolBridge` ile yapılır:
```swift
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, ya da OlafUI.presentExternal { ... } */ }
}
OlafUI.register(SomeToolBridge())
```
Gömülebilir SwiftUI araçları için `OlafUI.presentExternal { SomeView() }`; kendini sunan UIKit araçları için
`OlafUI.dismiss()` + aracın kendi `show()`'u.

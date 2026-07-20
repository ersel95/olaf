# Olaf — Entegrasyon Rehberi

Olaf'u uygulamaya bağlamak için rehber.

> **Tasarım ilkesi:** Olaf hiçbir dış araca bağlı değildir. Dış tanılama araçları
> (örn. başka bir network logger) jenerik `ExternalToolBridge` ile host tarafında eklenebilir.
> Hızlı yol: tek-dosya template [`Integration/OlafIntegration.swift`](Integration/OlafIntegration.swift)
> ve makine-takipli [`AGENTS.md`](AGENTS.md).

> **Gating notu:** TestFlight build'i genelde UAT/Prod config'tedir; `#if DEBUG` yalnız Test config'te tanımlıdır.
> Olaf'u `#if DEBUG`'a bağlama — `#if !PROD` derleme sınırı (önerilen, capture kodu prod binary'sine girmez)
> veya runtime feature flag kullan.

---

## 1. Paketi ekle

Xcode → Add Packages → `https://github.com/ersel95/olaf` → ana app target'ına ("Choose Package Products"):
- `Olaf` — **tek ürün**: motor + network capture + in-app viewer birlikte gelir.

> **Kapsam matrisi — hangi özellik hangi çağrı ile açılır:**
>
> | Özellik | Açma koşulu |
> |---|---|
> | Log API (trace…critical) | `Olaf.start(...)` |
> | Shake → log viewer | `OlafUI.install()` |
> | Network capture | `OlafNetwork.startAutomaticCapture()` |
> | Navigation breadcrumb | `Olaf.trackScreen(...)` (§6) |

## 2. Entegrasyon dosyasını kopyala

[`Integration/OlafIntegration.swift`](Integration/OlafIntegration.swift) dosyasını host app'e (örn. `Core/Utils/`)
kopyalayın. İçinde `OlafManager` (başlatma + loglama) hazırdır. `// ADAPT:` satırlarını uyarlayın.

```swift
@_exported import Olaf

public final class OlafManager {
    public static let shared = OlafManager()
    private init() {}

    public func initialize() {
        #if !PROD
        Olaf.start(.default)
        OlafNetwork.startAutomaticCapture()
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

İstek/yanıtları `.network` kategorisinde **ham** (maskelemesiz) loglar.

### ÖNERİLEN: tek satır otomatik capture (networking koduna dokunmadan)
`startAutomaticCapture()`, `URLSessionConfiguration`'ı swizzle ederek tüm session'lara (Alamofire dahil)
protokolü enjekte eder. Proxy session TLS doğrulamasını **sistem doğrulamasına bırakır**
(`.performDefaultHandling`) → capture katmanı host'un cert pinning'ini veya OS trust zincirini
**ezmez/baypaslamaz**; geçersiz sertifikalar yine reddedilir. (Not: Bu nedenle yalnızca cihazın
sistem trust zincirinin kabul ettiği sertifikalar yakalanır; host kendi özel pinning'ini
uyguluyorsa o trafik proxy üzerinden başarısız olabilir — bu beklenen ve güvenli davranıştır.)
`initialize` içinde hazır:
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

> **Güvenlik:** Gövde/header default açıktır → tüm trafik **ham** loglanır (maskeleme/filtreleme yapılmaz;
> token/PAN/IBAN/Authorization dahil her şey olduğu gibi saklanır). Capture katmanı TLS doğrulamasını
> ASLA gevşetmez (cert pinning baypaslanmaz). Hassas veri sızıntısını önlemek host'un sorumluluğundadır →
> capture **yalnız non-prod debug** içindir, PROD'da çalışmamalı.

> **Bilinen sınırlar:** WebSocket ve background session trafiği yakalanmaz (URLSession bunları
> URLProtocol'e yönlendirmez). `uploadTask(fromFile:)` gövdeleri yakalanmaz. Session-seviyesi ayarlar
> (`waitsForConnectivity` vb.) proxy'ye taşınmaz; çerezler paylaşılan `HTTPCookieStorage` ile korunur.
> Çok büyük upload gövdeleri için `capturesBodies: false` önerilir (stream RAM'e okunur).

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
Dosya `@_exported import Olaf` içerir → çağrı yerleri `import Olaf` yazmadan kullanabilir.

---

## 6. Navigation breadcrumb (ekran geçişleri)

`Olaf.trackScreen(_:kind:)` ekran geçişlerini `.navigation` kategorisinde loglar. SDK herhangi bir
navigasyon kütüphanesine **bağımlı değildir** (Coordinator'a import etmez); host kendi navigasyon
hook'undan çağırır.

### 6.1 Coordinator kullanan projeler (önerilen)
Host app'e küçük bir adapter ekleyin (Olaf'a değil — host target'a):
```swift
import CoordinatorCore   // host'un kendi navigasyon paketi
import Olaf

final class OlafNavigationObserver: CoordinatorActivityObserver {
    func coordinator(willPresentScreen id: String, kind: String) {
        Olaf.trackScreen(id, kind: kind)
    }
    func coordinator(didSwitchRoot id: String) {
        Olaf.trackScreen(id, kind: "root")
    }
    func coordinator(didDismissScreen id: String) {
        Olaf.trackScreen(id, kind: "dismiss")
    }
}
```
Kaydı `AppCoordinator` dispatcher kurulumuna **tek satır** (mevcut observer'ların yanına):
```swift
dispatcher.addActivityObserver(OlafNavigationObserver())
```
> Push (NavigationStack) ekranları modal kanalından gelmiyorsa: ya observer'ın
> `coordinatorDidObserveUserInteraction()`'ında `topMostViewInfo.screen.id` okuyup
> `Olaf.trackScreen(..., kind: "push")` çağırın, ya da `BaseCoordinator` stack `didSet`'ine tek
> `notify(kind:"push")` satırı ekleyin (host kararı).

### 6.2 Coordinator kullanmayan projeler (alternatif)
Ekran göründüğünde manuel çağırın:
```swift
.onAppear { Olaf.trackScreen("DashboardView", kind: "push") }
```

---

## 7. Doğrulama

1. `#if !PROD` aktif bir config'te (Debug/UAT) build alın.
2. Uygulamayı çalıştırın, birkaç ekranda gezinin (network/log birikir).
3. **Cihazı sallayın** → viewer açılır; app + network logları tek listede görünmelidir.
4. Bir network satırına girin → status banner, header'lar, pretty-JSON gövde ve paylaşım
   (Basit/Tam log + cURL) çalışmalıdır.

> **Sürüm uyumu:** iOS 17+. **Dış bağımlılık yok.** UIKit kodları `#if canImport(UIKit)` gate'lidir
> (non-UI mantık macOS'ta da derlenir/test edilir).

---

## 8. Köprüler (opsiyonel)

### 8.1 swift-log backend'i — `OlafLogHandler` (template)
Host swift-log kullanıyorsa [`Integration/OlafLogHandler.swift`](Integration/OlafLogHandler.swift)
dosyasını app'e kopyalayın (Olaf sıfır bağımlılık taşıdığından swift-log'a paket bağımlılığı yoktur;
swift-log host projede olmalıdır). Sonra uygulama başlangıcında, `Olaf.start` SONRASI bir kez:
```swift
LoggingSystem.bootstrap { label in OlafLogHandler(label: label) }
```
Uygulamadaki ve bağımlılıklardaki tüm `Logging.Logger` çağrıları Olaf'a akar; Logger `label`'ı
Olaf kategorisi olur, metadata korunur.

### 8.2 OSLog içe aktarma
Olaf'ı bilmeyen SDK'ların `os_log`/`Logger` çıktılarını da tek listede görmek için:
```swift
try await Olaf.importOSLogEntries(since: Date().addingTimeInterval(-3600))
```
Viewer menüsünde de var: **⋯ → "OSLog'u içe aktar (1 saat)"**. Olaf'ın kendi OSLog aynası çift
kayıt üretmesin diye ana bundle id'si (default ayna subsystem'i) otomatik hariç tutulur; aynaya
özel `subsystem` verdiyseniz `excludingSubsystems:` ile geçirin. Not: kayıtlar özgün zaman
damgasını taşır ama listede içe aktarma anının üstünde grup hâlinde görünür.

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

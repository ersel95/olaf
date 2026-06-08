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
- `OlafUpload` — **bug-reporter** (screenshot → banner → upload) için (§6). OPT-IN, varsayılan kapalı.

(App extension'lara yalnız `OlafCore`.)

> **Kapsam matrisi — hangi özellik hangi ürün/flag ile gelir:**
>
> | Özellik | Ürün(ler) | Açma koşulu |
> |---|---|---|
> | Log API (trace…critical) | `OlafCore` | `Olaf.start(...)` |
> | Shake → log viewer | `OlafCore` + `OlafUI` | `OlafUI.install()` |
> | Network capture | + `OlafNetwork` | `OlafNetwork.startAutomaticCapture()` |
> | Navigation breadcrumb | `OlafCore` | `Olaf.trackScreen(...)` (§7) |
> | **Bug-reporter** (screenshot→banner→upload) | + `OlafUpload` | `OlafUpload.configure(enabled: true, appKey:…)` (§6) — **opt-in** |

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

> **Güvenlik:** Gövde/header default açıktır → tüm trafik loglanır. BankingRedactor JSON gövdelerini derin,
> key-bazlı (token/balance/iban/pan/cvv…) maskeler ve kart/IBAN/email örüntülerini değerlerde gizler; yine de
> keyfi/serbest formatlı JSON'daki her PII'nin maskeleneceği garanti edilemez. Capture katmanı TLS doğrulamasını
> ASLA gevşetmez (cert pinning baypaslanmaz). Gövde loglama yine de **yalnız non-prod debug** içindir → PROD'da çalışmamalı.

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

## 6. Bug-reporter — screenshot → banner → upload (`OlafUpload`)

> **Akış:** Tester ekran görüntüsü alır → app'in altından **Olaf ikonu + balon** ("Bir sorun mu tespit
> edildi? Paylaşmak ister misin?") çıkar → **Evet** → 2 alanlı rapor sheet'i (+ ilk seferde isim) →
> ikisi de dolunca **Gönder** aktif → upload → başarıda sheet kapanır + "Gönderildi" toast'ı.
> Hata olursa rapor diske kuyruklanır ve daha sonra otomatik gönderilir (offline retry + backoff).

### 6.1 ÜÇ savunma katmanı (varsayılan KAPALI)
Bug-reporter **opt-in**'dir. `OlafUpload.configure(enabled: true, appKey:…)` çağrılmadıkça **hiçbir**
remote config / screenshot detector / upload kodu çalışmaz. Üç gate:
1. **Local opt-in** `enabled` (build-time, varsayılan `false`).
2. **`#if !PROD`** derleme sınırı (en kritik kural — canlıya asla çıkmaz).
3. **Server-side `captureEnabled`** (`GET /config?appKey=` ile uzaktan kill-switch).

`enabled == false` iken **sıfır ağ aktivitesi**: remote config bile çağrılmaz. `appKey` boşsa no-op + dev uyarısı.

### 6.2 Başlatma (opt-in configure)
`OlafManager.initialize()` template'i (§2) bunu zaten içerir; tek yapılacak değerleri **host tarafından**
sağlamak (§6.3). İlgili blok:
```swift
#if !PROD
Olaf.start(.bankingDefault)
#if canImport(OlafNetwork)
OlafNetwork.startAutomaticCapture()
#endif
Task { @MainActor in OlafUI.install() }   // bug-reporter detector hook'unu da kaydeder (kurmaz)

#if canImport(OlafUpload)
if let baseURL = Self.olafUploadBaseURL {       // değer yoksa hiç configure edilmez
    OlafUpload.configure(
        enabled: Self.bugReporterEnabled,        // default false — opt-in
        appKey: Self.olafAppKey,                 // host (xcconfig) sağlar
        apiKey: Self.olafApiKey,                 // host (xcconfig) sağlar
        baseURL: baseURL,                        // host (xcconfig) sağlar
        environment: Self.olafEnvironment
    )
}
#endif
#endif
```
> **Sıra bağımsız:** `OlafUI.install()` yalnız bir kurulum *hook'u* kaydeder; gerçek screenshot
> detector / banner ancak `OlafUpload.configure(enabled: true)` başarılı olunca kurulur. İkisinin
> çağrı sırası önemli değildir.

### 6.3 Konfig değerleri — HOST sağlar, repoya ASLA commit edilmez (public repo)
Olaf SDK **tamamen public**'tir → hiçbir gerçek URL / şirket adı / sır SDK koduna **veya** bu repoya girmez.
`appKey` / `apiKey` / `baseURL` host uygulamada runtime'da enjekte edilir. Önerilen yol: **xcconfig → Info.plist**.

1. Host repo'da (Olaf'ta değil) `Secrets.xcconfig` — **`.gitignore`'a ekleyin**:
   ```
   OLAF_BUG_REPORTER_ENABLED = true
   OLAF_APP_KEY = <APP_KEY>
   OLAF_API_KEY = <API_KEY>
   OLAF_API_BASE_URL = https:/$()/<your-olaf-host>     // xcconfig'te // yorum sayılır; $() ile kaçış
   OLAF_ENVIRONMENT = staging
   ```
2. `Info.plist`'e bu anahtarları `$(OLAF_APP_KEY)` vb. değişken referanslarıyla ekleyin.
3. Template'teki `Self.olafAppKey` vb. erişimciler bunları `Bundle.main.object(forInfoDictionaryKey:)` ile okur.

> CI/Fastlane kullanıyorsanız değerleri ortam değişkeninden xcconfig'e/Info.plist'e enjekte edin. Placeholder'lar
> (`<APP_KEY>`, `<your-olaf-host>`) **örnektir**; gerçek değerleri yalnız host CI/secrets'ta tutun.

### 6.4 Recursion önleme (otomatik)
`OlafUpload.configure`, upload + config endpoint'lerini (host + `/reports` + `/config`) otomatik olarak
`OlafNetwork.configuration.excludedURLs`'e ekler → upload trafiği capture edilmez (sonsuz döngü olmaz).
Ayrıca uploader **kendi `URLSession`'ını** kullanır (capture protokolü enjekte edilmemiş) → çift güvence.

---

## 7. Navigation breadcrumb (ekran geçişleri)

`Olaf.trackScreen(_:kind:)` ekran geçişlerini `.navigation` kategorisinde loglar. SDK herhangi bir
navigasyon kütüphanesine **bağımlı değildir** (Coordinator'a import etmez); host kendi navigasyon
hook'undan çağırır.

### 7.1 Coordinator kullanan projeler (önerilen)
Host app'e küçük bir adapter ekleyin (Olaf'a değil — host target'a):
```swift
import CoordinatorCore   // host'un kendi navigasyon paketi
import OlafCore

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

### 7.2 Coordinator kullanmayan projeler (alternatif)
Ekran göründüğünde manuel çağırın:
```swift
.onAppear { Olaf.trackScreen("DashboardView", kind: "push") }
```

---

## 8. Doğrulama & sorun giderme

### 8.1 Doğrulama adımları
1. `#if !PROD` aktif bir config'te (Debug/UAT) build alın; `OLAF_BUG_REPORTER_ENABLED = true` + `OLAF_APP_KEY`/
   `OLAF_API_KEY`/`OLAF_API_BASE_URL` sağlanmış olsun.
2. Uygulamayı çalıştırın, birkaç ekranda gezinin (network/log birikir).
3. **Ekran görüntüsü alın** (cihaz/simülatör: ⌘S simülatörde Save Screen).
   - **Görmelisin:** app'in altından Olaf ikonu + balon ("Bir sorun mu tespit edildi?…") yukarı kayar.
4. **Evet**'e basın → rapor sheet'i açılır. İlk kullanımda **isim** alanı görünür.
5. "Ne yaşadın?" + "Ne olmalıydı?" (ve gerekiyorsa isim) doldurun → **Gönder** aktifleşir.
6. **Gönder** → kısa loading → başarıda sheet kapanır + "Gönderildi" toast'ı.
   - **Görmelisin:** panelde (olaf-api'ye bağlı) yeni rapor; `entries` tüm kategorileri içerir, screenshot ekli.

### 8.2 Sorun giderme
- **Banner çıkmıyor**:
  - `OlafUpload.configure(enabled: true, …)` çağrıldı mı? `OlafUpload.isConfigured` `true` mu?
  - `appKey` dolu mu? (boşsa no-op + dev log uyarısı.)
  - Server-side `captureEnabled` `false` olabilir → `GET /config?appKey=` yanıtını kontrol edin
    (kill-switch). Banner yalnız `captureEnabled == true` iken gösterilir.
  - `#if !PROD` aktif mi? PROD config'te tüm akış derlenmez.
- **Screenshot siyah/eksik**: secure (gizli) alanlar `drawHierarchy` ile render'da siyah çıkabilir — bilinen, kabul edilen sınır.
- **Upload başarısız**: rapor **otomatik kuyruğa** alınır (`Caches/Olaf/uploads/`), exponential backoff ile
  yeniden denenir; sheet'te inline hata + "tekrar Gönder" gösterilir. Foreground'a dönüşte
  `OlafUpload.flushPendingUploads()` çağırarak bekleyenleri zorlayabilirsiniz.
- **Upload kendini logluyor (recursion)**: olmamalı — `configure` upload/config URL'lerini otomatik
  `excludedURLs`'e ekler. Yine de görürseniz `OlafNetwork.configuration.excludedURLs`'i kontrol edin.

> **Sürüm uyumu:** iOS 17+. **Dış bağımlılık yok.** UIKit kodları `#if canImport(UIKit)` gate'lidir
> (Core/Upload non-UI mantığı macOS'ta da derlenir/test edilir).

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

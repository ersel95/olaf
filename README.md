# LogFox 🦊📝

**Uygulama loglarını** cihazda görüntüleyip paylaşmayı sağlayan, generic ve taşınabilir bir Swift logging + in-app log viewer kütüphanesi.

> **Amaç:** TestFlight'a özelliği açık gönderdiğiniz kullanıcıların loglarını cihazda görüntüleyip paylaşabilmek. Cihaz sallandığında loglar düz metin olarak açılır.
>
> **Tamamen local:** Backend yoktur. Loglar cihazda NDJSON olarak saklanır (oturumlar arası geçmiş), viewer'dan okunur düz metin `.log` olarak paylaşılır. Hiçbir veri ağ üzerinden gönderilmez.

Tasarım/fizibilite detayları için ana projedeki `LOGFOX_REPORT.md`'ye bakın.

## Durum

| Faz | Kapsam | Durum |
|---|---|---|
| **0 — İskelet** | SPM, model'ler | ✅ |
| **1 — Core motor** | Ring buffer, redaksiyon, NDJSON disk persistans + oturumlar arası geçmiş, OSLog köprüsü, facade | ✅ |
| **2 — Viewer (LogFoxUI)** | Shake → SwiftUI düz metin viewer, **Oturum/Geçmiş** kapsamı, filtre/arama/paylaşım, canlı akış | ✅ |
| **3 — Araç köprüleri** | Jenerik `ExternalToolBridge` + `presentExternal`; host kendi dış tanılama aracını viewer'a buton olarak ekleyebilir, shake sahipliği devri (app tarafı: `INTEGRATION.md` / `AGENTS.md`) | ✅ |
| **N — Network capture (LogFoxNetwork)** | Opsiyonel URLProtocol; istek/yanıt `.network` kategorisinde, redaksiyonlu → app+network tek listede | ✅ |
| **5 — UX & paylaşım** | Detay görünümü (status banner, pretty-JSON gövde), paylaşım (Basit/Tam log + cURL), kopyalama toast, start öncesi log tamponlama, oturum bazlı geçmiş | ✅ |
| 4 — Köprüler | OSLogStore importer, swift-log backend | ⏳ |

## Kurulum (SPM)

```swift
.package(url: "https://github.com/ersel95/logfox.git", from: "0.17.0")
```
Ürünler: `LogFoxCore` (motor) · `LogFoxUI` (viewer) · `LogFoxNetwork` (opsiyonel network capture).

> Uygulamada doğrudan `LogFox.x(...)` çağırmak yerine tek entegrasyon noktası olan `LogFoxManager`
> üzerinden loglamanız önerilir — bkz. [`INTEGRATION.md`](INTEGRATION.md).

## Kullanım

```swift
import LogFoxCore

// Uygulama başlangıcında (bir kez):
LogFox.start(.bankingDefault)   // redaksiyon açık, diske yazar, OSLog'a yansıtır

// Loglama:
LogFox.info("Login başarılı", category: .auth, metadata: ["method": "biometric"])
LogFox.warning("Token yenilenecek", category: .session)
LogFox.error("Transfer reddedildi", category: .payment, metadata: ["code": code])

// Okuma / yönetim (viewer bunu kullanır):
let entries = LogFox.snapshot()              // bu oturum (bellek)
let history = LogFox.loadPersistedEntries()  // önceki oturumlar dahil (diskten)
for await entry in LogFox.stream() { … }     // canlı akış
let url = LogFox.exportFileURL()             // paylaşılabilir, okunur .log
LogFox.clear()

// Kill switch:
LogFox.isEnabled = false
```

### In-app viewer (LogFoxUI)

Shake → LogFox viewer. Host init'te kurar:

```swift
// Host entegrasyon dosyasında (Integration/LogFoxIntegration.swift):
LogFoxManager.shared.initialize()

// Paket API'si:
LogFoxUI.install()                             // shake → viewer
LogFoxUI.present(); LogFoxUI.dismiss()
LogFoxUI.presentExternal { SomeView() }        // gömülebilir SwiftUI araçları için
```

Shake sahibi LogFox'tur. Viewer'a kendi dış tanılama aracınızı eklemek için jenerik
`ExternalToolBridge` + `LogFoxUI.register(_:)` kullanın; buton viewer'ın **alt barında** görünür:

```swift
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, ya da LogFoxUI.presentExternal { ... } */ }
}
LogFoxUI.register(SomeToolBridge())
```

### Network loglarını LogFox'ta listelemek (LogFoxNetwork)

**Tek satır, networking koduna dokunmadan** (URLSessionConfiguration swizzle + global; SSL kırmaz):

```swift
import LogFoxNetwork
LogFoxNetwork.startAutomaticCapture()   // gövde+header default açık

// Hangi baseURL'lerin yakalanacağını init'te filtrele:
LogFoxNetwork.startAutomaticCapture(LogFoxNetworkConfiguration(
    capturesBodies: false,
    includedURLs: ["api-gateway"],                                   // yalnız kendi API'n (boş = tümü)
    excludedURLs: ["firebaseio", "crashlytics", "googleapis"]        // SDK gürültüsünü gizle
))
```
İstek/yanıtlar `.network` kategorisinde, **BankingRedactor'dan geçerek** LogFox listesine düşer
(app + network tek yerde). Gövde + header yakalama **default açık**; `Authorization`/`Cookie` ve
PAN/IBAN/token maskelenir. `includedURLs`/`excludedURLs` ile **baseURL filtreleme**, `excludedURLs`
önceliklidir; filtre dışı istekler hiç yakalanmaz.

- **JSON gövdeler** otomatik **pretty-print + syntax renklendirme** ile gösterilir (detay → "Gövdeyi görüntüle").
- Belirli bir config'e manuel enjeksiyon için `install(into:)` (gelişmiş) de var.
- **Yalnız non-prod debug** içindir (trust kabulü + gövde loglama) — PROD'da çalıştırmayın.

- **Adım adım entegrasyon:** [`INTEGRATION.md`](INTEGRATION.md)
- **AI agent için makine-takipli talimat:** [`AGENTS.md`](AGENTS.md)
- **Tek-dosya drop-in template:** [`Integration/LogFoxIntegration.swift`](Integration/LogFoxIntegration.swift)

## Mimari (Core)

```
LogFox (facade)
  └─ LogFoxRuntime          # yaşam döngüsü, kill switch, seviye eşiği (kilitle korunur)
       └─ LogStore          # serial kuyruk: redaksiyon → ring buffer → disk → OSLog → canlı akış
            ├─ Redactor               # BankingRedactor: PAN/IBAN/email/hassas-key maskeleme (redactionEnabled ile opt-in)
            ├─ FilePersistence        # boyut bazlı rotation + retention + data protection
            ├─ LogFormatter           # PlainText / JSON (NDJSON)
            └─ OSLogMirror            # os.Logger köprüsü (Console.app)
```

- **Banking-grade redaksiyon (opt-in)** — `LogFoxConfiguration(redactionEnabled: true)` (veya `.bankingDefault`) ile açılır; açıkken ham PII (PAN/CVV/IBAN/OTP/token) buffer'a, diske veya konsola asla yazılmaz. **Default `false`** → açıkça etkinleştirilmezse maskeleme yapılmaz.
- **UIKit/SwiftUI bağımlılığı yok** → her platformda derlenir, test edilebilir.
- **Async/non-blocking** — `@autoclosure` ile seviye eşiğin altındaysa mesaj compute edilmez; yazma serial kuyrukta.

## Geliştirme

```bash
swift build
swift test
```

## Lisans

TBD.

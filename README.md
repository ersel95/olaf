<p align="center">
  <img src="docs/olaf-logo.png" alt="Olaf" width="140">
</p>

# Olaf

[![CI](https://github.com/ersel95/olaf/actions/workflows/ci.yml/badge.svg)](https://github.com/ersel95/olaf/actions/workflows/ci.yml)

**Uygulama loglarını** cihazda görüntüleyip paylaşmayı sağlayan, generic ve taşınabilir bir Swift logging + in-app log viewer kütüphanesi. Değişiklikler için [CHANGELOG](CHANGELOG.md).

> **Amaç:** TestFlight'a özelliği açık gönderdiğiniz kullanıcıların loglarını cihazda görüntüleyip paylaşabilmek. Cihaz sallandığında loglar düz metin olarak açılır.
>
> **Tamamen local:** Backend yoktur. Loglar cihazda NDJSON olarak saklanır (oturumlar arası geçmiş), viewer'dan okunur düz metin `.log` olarak paylaşılır. Hiçbir veri ağ üzerinden gönderilmez.

## Durum

| Faz | Kapsam | Durum |
|---|---|---|
| **0 — İskelet** | SPM, model'ler | ✅ |
| **1 — Core motor** | Ring buffer, NDJSON disk persistans + oturumlar arası geçmiş, OSLog köprüsü, facade | ✅ |
| **2 — Viewer (OlafUI)** | Shake → SwiftUI düz metin viewer, **Oturum/Geçmiş** kapsamı (geçmiş sayfalı — sonsuz kaydırma), filtre/arama/paylaşım, canlı akış, simülatörde **Esc ile kapatma** | ✅ |
| **3 — Araç köprüleri** | Jenerik `ExternalToolBridge` + `presentExternal`; host kendi dış tanılama aracını viewer'a buton olarak ekleyebilir, shake sahipliği devri (app tarafı: `INTEGRATION.md` / `AGENTS.md`) | ✅ |
| **N — Network capture (OlafNetwork)** | Opsiyonel URLProtocol; istek/yanıt `.network` kategorisinde, ham → app+network tek listede | ✅ |
| **5 — UX & paylaşım** | Detay görünümü (status banner, pretty-JSON gövde), paylaşım (Basit/Tam log + cURL), kopyalama toast, start öncesi log tamponlama, oturum bazlı geçmiş | ✅ |
| **4 — Köprüler** | OSLogStore importer (`Olaf.importOSLogEntries` + viewer menüsü), swift-log backend (`Integration/OlafLogHandler.swift` template) | ✅ |

## Kurulum (SPM)

```swift
.package(url: "https://github.com/ersel95/olaf.git", from: "0.35.0")
```
Tek ürün: `Olaf` — motor (`Olaf` facade) + network capture (`OlafNetwork`) + viewer (`OlafUI`) birlikte gelir.

> Uygulamada doğrudan `Olaf.x(...)` çağırmak yerine tek entegrasyon noktası olan `OlafManager`
> üzerinden loglamanız önerilir — bkz. [`INTEGRATION.md`](INTEGRATION.md).

## Kullanım

```swift
import Olaf

// Uygulama başlangıcında (bir kez):
Olaf.start(.default)   // diske yazar, OSLog'a yansıtır

// Loglama:
Olaf.info("Login başarılı", category: .auth, metadata: ["method": "biometric"])
Olaf.warning("Token yenilenecek", category: .session)
Olaf.error("Transfer reddedildi", category: .payment, metadata: ["code": code])

// Okuma / yönetim (viewer bunu kullanır):
let entries = Olaf.snapshot()              // bu oturum (bellek)
let history = Olaf.loadPersistedEntries()  // önceki oturumlar dahil (diskten)
for await entry in Olaf.stream() { … }     // canlı akış
let url = Olaf.exportFileURL()             // paylaşılabilir, okunur .log
Olaf.clear()

// Kill switch:
Olaf.isEnabled = false
```

### In-app viewer (OlafUI)

Shake → Olaf viewer. Host init'te kurar:

```swift
// Host entegrasyon dosyasında (Integration/OlafIntegration.swift):
OlafManager.shared.initialize()

// Paket API'si:
OlafUI.install()                             // shake → viewer
OlafUI.present(); OlafUI.dismiss()
OlafUI.presentExternal { SomeView() }        // gömülebilir SwiftUI araçları için
```

Shake sahibi Olaf'tur. Viewer'a kendi dış tanılama aracınızı eklemek için jenerik
`ExternalToolBridge` + `OlafUI.register(_:)` kullanın; buton viewer'ın **alt barında** görünür:

```swift
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, ya da OlafUI.presentExternal { ... } */ }
}
OlafUI.register(SomeToolBridge())
```

### Network loglarını Olaf'ta listelemek (OlafNetwork)

**Tek satır, networking koduna dokunmadan** (URLSessionConfiguration swizzle + global; SSL kırmaz):

```swift
OlafNetwork.startAutomaticCapture()   // gövde+header default açık

// Hangi baseURL'lerin yakalanacağını init'te filtrele:
OlafNetwork.startAutomaticCapture(OlafNetworkConfiguration(
    capturesBodies: false,
    includedURLs: ["api-gateway"],                                   // yalnız kendi API'n (boş = tümü)
    excludedURLs: ["firebaseio", "crashlytics", "googleapis"]        // SDK gürültüsünü gizle
))
```
İstek/yanıtlar `.network` kategorisinde **ham** olarak Olaf listesine düşer
(app + network tek yerde). Gövde + header yakalama **default açık**; tüm veri (`Authorization`/`Cookie`
dahil) maskelenmeden saklanır. `includedURLs`/`excludedURLs` ile **baseURL filtreleme**, `excludedURLs`
önceliklidir; filtre dışı istekler hiç yakalanmaz.

- **JSON gövdeler** otomatik **pretty-print + syntax renklendirme** ile gösterilir (detay → "Gövdeyi görüntüle").
- **Aktif istekler**: devam eden (henüz yanıt almamış) istekler viewer'ın üstünde geçen süresiyle canlı görünür — asılı kalan çağrıyı anında yakalarsınız.
- **Zamanlama kırılımı**: her istekte DNS / TCP / TLS / TTFB süreleri, protokol (h2/h3) ve bağlantının yeniden kullanılıp kullanılmadığı detay ekranındaki "Zamanlama" bölümünde ("API mi yavaş, ağ mı?").
- Belirli bir config'e manuel enjeksiyon için `install(into:)` (gelişmiş) de var.
- **Yalnız non-prod debug** içindir (gövde/header loglama) — PROD'da çalıştırmayın.

#### Bilinen sınırlar (URLProtocol tabanlı yakalamanın doğası)
- **WebSocket** (`URLSessionWebSocketTask`) ve **background session** trafiği yakalanmaz (URLSession bu trafiği URLProtocol'e yönlendirmez).
- `uploadTask(fromFile:)` / upload stream gövdeleri yakalanmaz; `httpBody`/`httpBodyStream` gövdeleri yakalanır (stream tamamen RAM'e okunur — çok büyük upload'larda `capturesBodies: false` önerilir).
- Host session'ın **session-seviyesi ayarları** (`waitsForConnectivity`, `allowsCellularAccess` vb.) proxy'ye taşınmaz; isteğin kendi `timeoutInterval`'ı korunur. Çerezler paylaşılan `HTTPCookieStorage` üzerinden korunur.
- Host **özel cert pinning** uyguluyorsa proxy o trafiği geçiremeyebilir (proxy host'un trust delegate'ini paylaşmaz; sistem doğrulaması uygulanır — güvenli ve bilinçli davranış).

- **Adım adım entegrasyon:** [`INTEGRATION.md`](INTEGRATION.md)
- **AI agent için makine-takipli talimat:** [`AGENTS.md`](AGENTS.md)
- **Tek-dosya drop-in template:** [`Integration/OlafIntegration.swift`](Integration/OlafIntegration.swift)

## Mimari (Core)

```
Olaf (facade)
  └─ OlafRuntime          # yaşam döngüsü, kill switch, seviye eşiği (kilitle korunur)
       └─ LogStore          # serial kuyruk: ring buffer → disk → OSLog → canlı akış (ham, maskelemesiz)
            ├─ FilePersistence        # boyut bazlı rotation + retention + data protection
            ├─ LogFormatter           # PlainText / JSON (NDJSON)
            └─ OSLogMirror            # os.Logger köprüsü (Console.app)
```

- **Maskeleme/filtreleme yok** — mesaj, metadata ve network gövde/header çağrı yerinden geldiği gibi **ham** saklanır ve gösterilir. Hassas veri sızıntısını önlemek host tarafının sorumluluğundadır: capture'ı yalnız non-prod debug'da (`#if !PROD`) çalıştırın.
- **UIKit/SwiftUI bağımlılığı yok** → her platformda derlenir, test edilebilir.
- **Async/non-blocking** — `@autoclosure` ile seviye eşiğin altındaysa mesaj compute edilmez; yazma serial kuyrukta.

## Geliştirme

```bash
swift build
swift test
```

## Lisans

MIT — bkz. [LICENSE](LICENSE).

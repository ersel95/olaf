# LogFox 🦊📝

Netfox'un network trafiği için yaptığını **uygulama logları** için yapan, generic, taşınabilir bir Swift logging + in-app log viewer kütüphanesi.

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
| **3 — Araç köprüleri** | `ExternalToolBridge` + `install(tools:)` + `presentExternal` → **Netfox & Pulse** geçişi, shake sahipliği devri (app tarafı: `INTEGRATION.md` / `AGENTS.md`) | ✅ |
| **N — Network capture (LogFoxNetwork)** | Opsiyonel URLProtocol; istek/yanıt `.network` kategorisinde, redaksiyonlu → app+network tek listede | ✅ |
| **5 — UX & paylaşım** | Pulse tarzı detay (status banner, pretty-JSON gövde), Netfox tarzı paylaşım (Basit/Tam log + cURL), kopyalama toast, start öncesi log tamponlama, oturum bazlı geçmiş | ✅ |
| 4 — Köprüler | OSLogStore importer, swift-log backend | ⏳ |

## Kurulum (SPM)

```swift
.package(url: "https://github.com/ersel95/logfox.git", from: "0.9.0")
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

### In-app viewer (LogFoxUI) + Netfox / Pulse geçişi

LogFox, **Netfox** ve **Pulse** ile uyumludur. Paket bunlara bağlı değildir. Bir projede **yalnız bir**
network logger aktiftir; host bunu bir enum ile init'te seçer. Köprüler host tarafında `#if canImport`
ile tanımlıdır (`Integration/LogFoxIntegration.swift`):

```swift
// Host entegrasyon dosyasında:
public enum LogFoxNetworkLogger { case netfox, pulse, none }

LogFoxManager.shared.initialize(networkLogger: .netfox)   // .netfox / .pulse / .none

// Paket API'si (host köprüleri bununla kaydeder):
LogFoxUI.install(tools: bridges)              // shake → viewer
LogFoxUI.present(); LogFoxUI.dismiss()
LogFoxUI.presentExternal { ConsoleView() }    // Pulse gibi gömülebilir araçlar için
```

Shake sahibi LogFox'tur; viewer içinden **seçilen tek** araca (Netfox **veya** Pulse) geçilir.
Geçiş butonu artık ••• menüsünde değil, viewer'ın **alt barında** belirgindir.
Netfox kullanılıyorsa shake'ini kapatın (`NFX.sharedInstance().setGesture(.custom)`).

### Network loglarını LogFox'ta listelemek (LogFoxNetwork)

```swift
import LogFoxNetwork
LogFoxNetwork.install(into: sessionConfiguration)   // gövde+header default açık; veya .installGlobally()
// parametreleri init'te kısmak için:
LogFoxNetwork.install(into: sessionConfiguration, with: LogFoxNetworkConfiguration(capturesBodies: false))
```
İstek/yanıtlar `.network` kategorisinde, **BankingRedactor'dan geçerek** LogFox listesine düşer
(app + network tek yerde). Gövde + header yakalama **default açık**; `Authorization`/`Cookie` ve
PAN/IBAN/token maskelenir. Yakalama parametreleri `install(into:with:)` ile init'te verilir.

- **Adım adım entegrasyon:** [`INTEGRATION.md`](INTEGRATION.md)
- **AI agent için makine-takipli talimat:** [`AGENTS.md`](AGENTS.md)
- **Tek-dosya drop-in template:** [`Integration/LogFoxIntegration.swift`](Integration/LogFoxIntegration.swift)

## Mimari (Core)

```
LogFox (facade)
  └─ LogFoxRuntime          # yaşam döngüsü, kill switch, seviye eşiği (kilitle korunur)
       └─ LogStore          # serial kuyruk: redaksiyon → ring buffer → disk → OSLog → canlı akış
            ├─ Redactor               # BankingRedactor: PAN/IBAN/email/hassas-key maskeleme (default)
            ├─ FilePersistence        # boyut bazlı rotation + retention + data protection
            ├─ LogFormatter           # PlainText / JSON (NDJSON)
            └─ OSLogMirror            # os.Logger köprüsü (Console.app)
```

- **Banking-grade redaksiyon varsayılan açık** — ham PII (PAN/CVV/IBAN/OTP/token) buffer'a, diske veya konsola asla yazılmaz.
- **UIKit/SwiftUI bağımlılığı yok** → her platformda derlenir, test edilebilir.
- **Async/non-blocking** — `@autoclosure` ile seviye eşiğin altındaysa mesaj compute edilmez; yazma serial kuyrukta.

## Geliştirme

```bash
swift build
swift test
```

## Lisans

TBD.

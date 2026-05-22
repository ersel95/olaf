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
| 4 — Köprüler | OSLogStore importer, swift-log backend | ⏳ |

## Kurulum (SPM)

```swift
.package(url: "https://github.com/ersel95/logfox.git", from: "0.1.0")
```
Target bağımlılığı: `LogFoxCore`.

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

LogFox, **Netfox** ve **Pulse** ile uyumludur. Paket bunlara bağlı değildir; host app `#if canImport`
ile hangilerinin yüklü olduğunu tespit eder ve etkin geçiş köprülerini **init'te** gönderir:

```swift
import LogFoxUI

var tools: [any ExternalToolBridge] = []
#if canImport(netfox)
if config.enableNetfox { tools.append(NetfoxBridge()) }   // app tarafında tanımlı köprü
#endif
#if canImport(PulseUI)
if config.enablePulse  { tools.append(PulseBridge())  }
#endif

LogFoxUI.install(tools: tools)   // shake → viewer; karar pakete init'te gönderilir

// Programatik:
LogFoxUI.present()
LogFoxUI.dismiss()
LogFoxUI.presentExternal { ConsoleView() }   // Pulse gibi gömülebilir araçlar için
```

Shake sahibi LogFox'tur; viewer içinden **yalnız link'li ve etkin** araçlara (Netfox/Pulse) geçilir.
Netfox kullanılıyorsa shake'ini kapatın (`NFX.sharedInstance().setGesture(.custom)`).

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

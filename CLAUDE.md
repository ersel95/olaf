# LogFox — AI Asistan Notları

Generic, taşınabilir Swift logging + in-app log viewer paketi. Netfox'un network için yaptığını
**uygulama logları** için yapar; opsiyonel olarak network'ü de yakalar. Tamamen **local** (backend yok).

## Ürünler / hedefler
- **LogFoxCore** — UIKit'siz motor: `LogFox` facade, ring buffer, `BankingRedactor`, NDJSON disk persistans
  (oturum bazlı geçmiş), OSLog köprüsü, start-öncesi log tamponlama. Her platformda derlenir/test edilir.
- **LogFoxUI** — SwiftUI viewer (shake → liste/detay, filtre, paylaşım). Tüm içerik `#if canImport(UIKit)` gate'li.
- **LogFoxNetfox** — opsiyonel Netfox köprü ürünü (`Sources/LogFoxNetfox/`). netfox'a bağlı; "Choose Package
  Products"ta ayrı ürün olarak görünür. Tüketici target'a ekler + `LogFoxNetfox.install()` çağırır → viewer'da
  "Netfox" butonu. `NetfoxBridge` + köprü gövdesi `#if canImport(UIKit)` gate'li (netfox iOS-only). Bkz. Sürümleme.
- **LogFoxNetwork** — opsiyonel URLProtocol network capture; `.network` kategorisinde, redaksiyonlu.
  - `startAutomaticCapture(config)` — URLSessionConfiguration swizzle ile tüm session'lara otomatik enjekte (host'un networking koduna dokunmadan); proxy session sunucu trust'ını kabul eder (SSL kırmaz).
  - `LogFoxNetworkConfiguration`: `capturesBodies/capturesHeaders` (default açık), `includedURLs`/`excludedURLs` (baseURL allow/deny filtresi — `canInit`'te uygulanır, exclude önceliklidir), `maxBodyLength`, `category`.
  - JSON gövdeler **yakalama anında** pretty-print edilip saklanır; viewer'da `JSONHighlighter` ile syntax renklendirme.

## Build / test
```bash
swift build && swift test                    # macOS — netfox iOS-only, LogFoxNetfox boş köprüyle derlenir
xcodebuild -scheme LogFoxUI -destination 'generic/platform=iOS' build      # iOS viewer doğrulama
xcodebuild -scheme LogFoxNetfox -destination 'generic/platform=iOS' build  # iOS Netfox köprüsü (netfox + NFX)
```
Her değişiklikte macOS test + iOS build yeşil olmalı. netfox UIKit-only olduğu için **macOS'ta derlenmez**
(target bağımlılığı `.when(platforms: [.iOS])` ile koşullu; köprü gövdesi `#if canImport(UIKit)`).

## Değişmez kurallar
- **Redaksiyon default açık** (PAN/IBAN/email/Authorization/Cookie/token). Ham PII buffer'a/diske/konsola yazılmaz.
- **Netfox bağımlılığı OPSİYONEL ve ürün-izole.** netfox yalnız `LogFoxNetfox` target'ına bağlıdır; LogFoxCore/UI/
  Network netfox'a DOKUNMAZ. Tüketici `LogFoxNetfox` ürününü seçmezse netfox **linklenmez/derlenmez** (yalnız
  resolution'da checkout edilir). Trait DENENDİ ama `.xcodeproj` tüketicisi trait'i UI'dan açamadığı için ayrı
  ürün modeline geçildi (manifest `5.9`). **Kod kopyalanmaz**, netfox'a yalnız `.product(...)` ile referans verilir.
- **Köprü ayrı üründe, host'ta `import netfox` YOK.** `NetfoxBridge` artık `Sources/LogFoxNetfox/` içinde,
  `#if canImport(UIKit)` gate'li. Swift modülü linklenince kendi kodunu otomatik çalıştıramadığı için host init'te
  **tek satır** `LogFoxNetfox.install()` çağırır (`LogFoxUI.register` ile köprüyü kaydeder). App yine `LogFox`'a
  değil host'taki `LogFoxManager` üzerinden loglar. Bkz. `INTEGRATION.md`, `AGENTS.md`, `Integration/`.
- **Network capture yalnız non-prod debug.** Proxy session sunucu trust'ını kabul eder (SSL kırmamak için);
  gövde/header default loglanır → PROD'da çalıştırılmamalı (host runtime flag + `#if !PROD` ile gate'ler).
- **call-site bilgisi** (file/line/function) log fonksiyonlarında **doğrudan** `#fileID/#line/#function` default'u
  olmalı — tek struct'a sarmak (LogSource) call-site yakalamayı bozar.
- Public repo: banka/şirket adı veya iç sınıf adı **eklenmez** (jenerik tut).

## Sürümleme
SemVer + git tag. Sources değişince tag at (`0.x.0`); yalnız doküman/template değişince tag gerekmez.
`Integration/LogFoxIntegration.swift` SPM ürünü DEĞİLDİR (host'a kopyalanan template) — Sources dışında.

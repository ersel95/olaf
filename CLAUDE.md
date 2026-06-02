# LogFox — AI Asistan Notları

Generic, taşınabilir Swift logging + in-app log viewer paketi. **Uygulama loglarını** cihazda
görüntüleyip paylaşmayı sağlar; opsiyonel olarak network'ü de yakalar. Tamamen **local** (backend yok).

## Ürünler / hedefler
- **LogFoxCore** — UIKit'siz motor: `LogFox` facade, ring buffer, `BankingRedactor`, NDJSON disk persistans
  (oturum bazlı geçmiş), OSLog köprüsü, start-öncesi log tamponlama. Her platformda derlenir/test edilir.
- **LogFoxUI** — SwiftUI viewer (shake → liste/detay, filtre, paylaşım). Tüm içerik `#if canImport(UIKit)` gate'li.
  Jenerik `ExternalToolBridge` + `LogFoxUI.register(_:)` ile host kendi dış tanılama aracını viewer'a
  buton olarak ekleyebilir (paket hiçbir dış araca bağlı değildir).
- **LogFoxNetwork** — opsiyonel URLProtocol network capture; `.network` kategorisinde, redaksiyonlu.
  - `startAutomaticCapture(config)` — URLSessionConfiguration swizzle ile tüm session'lara otomatik enjekte (host'un networking koduna dokunmadan); proxy session sunucu trust'ını kabul eder (SSL kırmaz).
  - `LogFoxNetworkConfiguration`: `capturesBodies/capturesHeaders` (default açık), `includedURLs`/`excludedURLs` (baseURL allow/deny filtresi — `canInit`'te uygulanır, exclude önceliklidir), `maxBodyLength`, `category`.
  - JSON gövdeler **yakalama anında** pretty-print edilip saklanır; viewer'da `JSONHighlighter` ile syntax renklendirme.

## Build / test
```bash
swift build && swift test                                              # macOS
xcodebuild -scheme LogFoxUI -destination 'generic/platform=iOS' build  # iOS viewer doğrulama
```
Her değişiklikte macOS test + iOS build yeşil olmalı.

## Değişmez kurallar
- **Redaksiyon default açık** (PAN/IBAN/email/Authorization/Cookie/token). Ham PII buffer'a/diske/konsola yazılmaz.
- **Paket hiçbir dış araca bağlı DEĞİLDİR.** Dış tanılama aracı geçişi yalnız jenerik `ExternalToolBridge`
  + `LogFoxUI.register(_:)` ile host tarafında eklenir; gerekirse `LogFoxNetwork.install(chainingTo:)` ile
  başka bir capture aracının URLProtocol'ü paylaşılan session'a zincirlenebilir.
- **Network capture yalnız non-prod debug.** Proxy session sunucu trust'ını kabul eder (SSL kırmamak için);
  gövde/header default loglanır → PROD'da çalıştırılmamalı (host runtime flag + `#if !PROD` ile gate'ler).
- **call-site bilgisi** (file/line/function) log fonksiyonlarında **doğrudan** `#fileID/#line/#function` default'u
  olmalı — tek struct'a sarmak (LogSource) call-site yakalamayı bozar.
- Public repo: banka/şirket adı veya iç sınıf adı **eklenmez** (jenerik tut).

## Sürümleme
SemVer + git tag. Sources değişince tag at (`0.x.0`); yalnız doküman/template değişince tag gerekmez.
`Integration/LogFoxIntegration.swift` SPM ürünü DEĞİLDİR (host'a kopyalanan template) — Sources dışında.

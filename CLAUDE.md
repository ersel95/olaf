# Olaf — AI Asistan Notları

Generic, taşınabilir Swift logging + in-app log viewer paketi. **Uygulama loglarını** cihazda
görüntüleyip paylaşmayı sağlar; opsiyonel olarak network'ü de yakalar. Tamamen **local** (backend yok).

## Ürünler / hedefler
- **OlafCore** — UIKit'siz motor: `Olaf` facade, ring buffer, NDJSON disk persistans
  (oturum bazlı geçmiş), OSLog köprüsü, start-öncesi log tamponlama. Her platformda derlenir/test edilir.
- **OlafUI** — SwiftUI viewer (shake → liste/detay, filtre, paylaşım). Tüm içerik `#if canImport(UIKit)` gate'li.
  Jenerik `ExternalToolBridge` + `OlafUI.register(_:)` ile host kendi dış tanılama aracını viewer'a
  buton olarak ekleyebilir (paket hiçbir dış araca bağlı değildir).
- **OlafNetwork** — opsiyonel URLProtocol network capture; `.network` kategorisinde, ham (maskelemesiz).
  - `startAutomaticCapture(config)` — URLSessionConfiguration swizzle ile tüm session'lara otomatik enjekte (host'un networking koduna dokunmadan); proxy session sunucu trust'ını kabul eder (SSL kırmaz).
  - `OlafNetworkConfiguration`: `capturesBodies/capturesHeaders` (default açık), `includedURLs`/`excludedURLs` (baseURL allow/deny filtresi — `canInit`'te uygulanır, exclude önceliklidir), `maxBodyLength`, `category`.
  - JSON gövdeler **yakalama anında** pretty-print edilip saklanır; viewer'da `JSONHighlighter` ile syntax renklendirme.

## Build / test
```bash
swift build && swift test                                              # macOS
xcodebuild -scheme OlafUI -destination 'generic/platform=iOS' build  # iOS viewer doğrulama
```
Her değişiklikte macOS test + iOS build yeşil olmalı.

## Değişmez kurallar
- **Redaksiyon/maskeleme/filtreleme YOK.** Tüm veri çağrı yerinden geldiği gibi **ham** saklanır ve gösterilir (mesaj, metadata, network gövde/header). Maskeleme bir seçenek olarak bile sunulmaz — `Redactor`/`BankingRedactor`/`redactionEnabled` API'si bilinçli olarak kaldırılmıştır; geri eklenmez. Hassas veri sızıntısı host tarafının sorumluluğundadır (PROD'da capture'ı `#if !PROD` ile gate'leyin).
- **Paket hiçbir dış araca bağlı DEĞİLDİR.** Dış tanılama aracı geçişi yalnız jenerik `ExternalToolBridge`
  + `OlafUI.register(_:)` ile host tarafında eklenir; gerekirse `OlafNetwork.install(chainingTo:)` ile
  başka bir capture aracının URLProtocol'ü paylaşılan session'a zincirlenebilir.
- **Network capture yalnız non-prod debug.** Proxy session sunucu trust'ını kabul eder (SSL kırmamak için);
  gövde/header default loglanır → PROD'da çalıştırılmamalı (host runtime flag + `#if !PROD` ile gate'ler).
- **call-site bilgisi** (file/line/function) log fonksiyonlarında **doğrudan** `#fileID/#line/#function` default'u
  olmalı — tek struct'a sarmak (LogSource) call-site yakalamayı bozar.
- Public repo: banka/şirket adı veya iç sınıf adı **eklenmez** (jenerik tut).

## Sürümleme
SemVer + git tag. Sources değişince tag at (`0.x.0`); yalnız doküman/template değişince tag gerekmez.
`Integration/OlafIntegration.swift` SPM ürünü DEĞİLDİR (host'a kopyalanan template) — Sources dışında.

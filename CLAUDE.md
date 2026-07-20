# Olaf — AI Asistan Notları

Generic, taşınabilir Swift **network logger** paketi: uygulama + network loglarını cihazda
görüntüleyip paylaşmayı sağlar. Tamamen **local** (backend yok, hiçbir veri ağ üzerinden gönderilmez).

> Eskiden pakette bulunan bug-reporter/upload mekanizması (hataları backend'e bildirme) bilinçli
> olarak **kaldırılmıştır** ve ayrı bir projede geliştirilecektir — özet: `docs/bug-reporter-ozet.md`.
> Olaf'a geri eklenmez.

## Yapı — TEK ürün, TEK target
SPM tek ürün sunar: `Olaf`. Host tek ürünü ekler, tek `import Olaf` yeter. Target içi klasörler:
- **`Sources/Olaf/Core`** — UIKit'siz motor: `Olaf` facade, ring buffer, NDJSON disk persistans
  (oturum bazlı geçmiş), OSLog köprüsü, start-öncesi log tamponlama. Her platformda derlenir/test edilir.
- **`Sources/Olaf/UI`** — SwiftUI viewer (shake → liste/detay, filtre, paylaşım). Tüm içerik
  `#if canImport(UIKit)` gate'li. Jenerik `ExternalToolBridge` + `OlafUI.register(_:)` ile host kendi
  dış tanılama aracını viewer'a buton olarak ekleyebilir (paket hiçbir dış araca bağlı değildir).
- **`Sources/Olaf/Network`** — URLProtocol network capture; `.network` kategorisinde, ham (maskelemesiz).
  - `startAutomaticCapture(config)` — URLSessionConfiguration swizzle ile tüm session'lara otomatik enjekte (host'un networking koduna dokunmadan). Yakalanan istekler TEK paylaşılan proxy session'dan (`OlafProxySession`) geçer: bağlantı havuzu/TLS yeniden kullanılır, paylaşılan `HTTPCookieStorage` korunur. Trust default sistem doğrulamasıdır (`allowsArbitraryServerTrustForCapture` yalnız opt-in).
  - `OlafNetworkConfiguration`: `capturesBodies/capturesHeaders` (default açık), `includedURLs`/`excludedURLs` (baseURL allow/deny filtresi — `canInit`'te uygulanır, exclude önceliklidir), `maxBodyLength`, `category`.
  - JSON gövdeler **yakalama anında** pretty-print edilip saklanır; viewer'da `JSONHighlighter` ile syntax renklendirme.

## Build / test
```bash
swift build && swift test                                          # macOS
xcodebuild -scheme Olaf -destination 'generic/platform=iOS' build  # iOS doğrulama
```
Her değişiklikte macOS test + iOS build yeşil olmalı.

## Değişmez kurallar
- **Tek SPM ürünü/target'ı kalır.** Paket yeniden ürünlere bölünmez; upload/bug-reporter geri eklenmez.
- **Redaksiyon/maskeleme/filtreleme YOK.** Tüm veri çağrı yerinden geldiği gibi **ham** saklanır ve gösterilir (mesaj, metadata, network gövde/header). Maskeleme bir seçenek olarak bile sunulmaz — `Redactor`/`BankingRedactor`/`redactionEnabled` API'si bilinçli olarak kaldırılmıştır; geri eklenmez. Hassas veri sızıntısı host tarafının sorumluluğundadır (PROD'da capture'ı `#if !PROD` ile gate'leyin).
- **Paket hiçbir dış araca bağlı DEĞİLDİR.** Dış tanılama aracı geçişi yalnız jenerik `ExternalToolBridge`
  + `OlafUI.register(_:)` ile host tarafında eklenir; gerekirse `OlafNetwork.install(chainingTo:)` ile
  başka bir capture aracının URLProtocol'ü paylaşılan session'a zincirlenebilir.
- **Network capture yalnız non-prod debug.** Proxy varsayılan olarak sistem trust doğrulaması kullanır
  (pinning/OS trust baypaslanmaz); özel CA'lar için `allowsArbitraryServerTrustForCapture` opt-in'dir.
  Gövde/header default loglanır → PROD'da çalıştırılmamalı (host runtime flag + `#if !PROD` ile gate'ler).
- **call-site bilgisi** (file/line/function) log fonksiyonlarında **doğrudan** `#fileID/#line/#function` default'u
  olmalı — tek struct'a sarmak (LogSource) call-site yakalamayı bozar.
- Public repo: banka/şirket adı veya iç sınıf adı **eklenmez** (jenerik tut).

## Sürümleme
SemVer + git tag. Sources değişince tag at (`0.x.0`); yalnız doküman/template değişince tag gerekmez.
`Integration/OlafIntegration.swift` SPM ürünü DEĞİLDİR (host'a kopyalanan template) — Sources dışında.

# Changelog

Biçim [Keep a Changelog](https://keepachangelog.com/tr/) esinlidir; sürümleme SemVer'dir
(0.x — API henüz stabil değildir). Daha eski sürümler için git tag geçmişine bakın.

## [0.35.0] — 2026-07-20
### Eklendi
- **Geçmişte sayfalama**: `Olaf.loadPersistedPage(before:minimumEntries:)` — geçmiş artık tek
  seferde değil, en yeniden geriye dosya-sınırlı imleçle sayfa sayfa yüklenir. Viewer'da sonsuz
  kaydırma + "Daha eskileri yükle" satırı; arama/filtrelerin yüklenen kayıtlarda çalıştığı
  bilgi notu. Sayfalar arasında rotation olsa bile kayıt tekrarı oluşmaz.
- **Esc ile kapatma**: donanım klavyesi (simülatörde Mac klavyesi) Esc'i viewer'ı kapatır;
  `presentExternal` ile açılan dış araçta Esc önce aracı kapatıp viewer'a döner.

## [0.34.0] — 2026-07-20
### Eklendi
- `PrivacyInfo.xcprivacy` — SDK privacy manifest'i (veri toplanmaz, tracking yok; yalnız
  rotation için dosya-tarihi okuma beyanı `C617.1`).
- DocC kataloğu (`Olaf.docc`) — API dokümantasyonu landing page + konu grupları.
- `CHANGELOG.md` (bu dosya) ve README'ye CI rozeti.

## [0.33.0] — 2026-07-20
### Eklendi
- **OSLogStore importer**: `Olaf.importOSLogEntries(since:category:excludingSubsystems:)` —
  bu sürecin OSLog kayıtlarını (diğer SDK'ların `os_log` çıktıları dahil) Olaf'a aktarır;
  viewer menüsünde "OSLog'u içe aktar (1 saat)". `LogCategory.oslog` eklendi.
- **swift-log backend template'i**: `Integration/OlafLogHandler.swift` —
  `LoggingSystem.bootstrap` ile tüm `Logging.Logger` çağrıları Olaf'a akar
  (sıfır-bağımlılık kuralı gereği paket bağımlılığı değil, host'a kopyalanan template).

## [0.32.0] — 2026-07-20
### Eklendi
- `Olaf.minimumLevel` — toplama eşiği runtime'da değiştirilebilir; filtre ekranında
  "Toplama eşiği" ayarı.
- NDJSON export: `Olaf.exportNDJSONFileURL(entries:)` + viewer'da "Paylaş (NDJSON)".
### Değişti
- Viewer türetilmiş değerleri (`filteredEntries`/`sessionGroups`/`availableCategories`)
  memoize edildi: render başına değil, girdi değişince bir kez hesaplanır (büyük Geçmiş'te
  takılma önlenir).

## [0.31.0] — 2026-07-20
### Eklendi
- **Aktif istekler barı**: devam eden istekler viewer üstünde geçen süresiyle canlı görünür
  (`OlafNetwork.pendingRequests`); asılı istekler anında fark edilir.
- **Zamanlama kırılımı**: `URLSessionTaskMetrics`'ten DNS / TCP / TLS / TTFB, protokol
  (h2/h3) ve bağlantı yeniden kullanımı — detay ekranında "Zamanlama" bölümü.
- README/INTEGRATION: URLProtocol yakalamasının bilinen sınırları dokümante edildi.

## [0.30.0] — 2026-07-20
### Değişti
- **Paylaşılan proxy session** (`OlafProxySession`): istek başına ephemeral session yerine tek
  session — bağlantı havuzu/TLS yeniden kullanımı; paylaşılan `HTTPCookieStorage` korunur
  (cookie tabanlı oturumlar capture altında bozulmaz).
- İptal edilen istekler (`NSURLErrorCancelled`) `.error` değil `.info` ("→ iptal") loglanır.
- Swift 6 concurrency uyarıları sıfırlandı (delegate conformance yönetici sınıfa taşındı).
### Eklendi
- GitHub Actions CI (macOS test + iOS build) ve network katmanı testleri.

## [0.29.0] — 2026-07-20
### Kaldırıldı (BREAKING)
- Bug-reporter/upload mekanizması (`OlafUpload` target'ı, BugReport UI akışı,
  `ScreenshotDetector`, `LogCategory.screenshot`) — ayrı bir projede geliştirilecek;
  özet: `docs/bug-reporter-ozet.md`.
### Değişti (BREAKING)
- Tek SPM ürünü/target'ı: `OlafCore` + `OlafUI` + `OlafNetwork` → `Olaf`
  (host tek ürün ekler, tek `import Olaf`).

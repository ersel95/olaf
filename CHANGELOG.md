# Changelog

Biçim [Keep a Changelog](https://keepachangelog.com/tr/) esinlidir; sürümleme SemVer'dir
(0.x — API henüz stabil değildir). Daha eski sürümler için git tag geçmişine bakın.

## [0.43.0] — 2026-07-20
### Eklendi
- **Viewer'dan mock'a çevirme**: network kaydının detayında "Mock'a çevir" — yakalanan yanıt
  düzenlenebilir editörde açılır (URL kalıbı, metot kısıtı, status/gövde, gecikme, taşıma
  hatası seçimi) ve kaydedilince cihaz üzerinde, kod yazmadan mock aktifleşir.
- **Mock listesi** (⋯ → Mock'lar): aktif mock'ları görüntüleme, kaydırarak tekil silme,
  "Tümünü kaldır". `OlafMockResponse` artık `Identifiable`; `OlafNetwork.removeMock(id:)`.

## [0.42.0] — 2026-07-20
### Eklendi
- **Response mocking**: `OlafNetwork.addMock(OlafMockResponse(...))` — eşleşen istekler ağa
  çıkmadan tanımlı yanıtı alır (status/header/gövde, `delaySeconds` ile yavaş ağ,
  `.failure(...)` ile taşıma hatası simülasyonu). İlk eklenen mock kazanır; capture URL
  filtreleri mock'ları etkilemez. Kayıtlar `[mock]` işaretiyle loglanır, detayda
  "Kaynak: Mock" görünür.

## [0.41.0] — 2026-07-20
### Eklendi
- **Sabitleme (pin)**: satıra basılı tutup "Sabitle" — sabitler oturum listesinin üstünde,
  filtrelerden bağımsız ayrı bölümde görünür (oturum içi; kalıcı değildir).
- **Çoklu seçim paylaşımı** (⋯ → Seç): oturum listesinde birden çok kayıt işaretlenip tek
  `.log` dosyası olarak paylaşılabilir.

## [0.40.0] — 2026-07-20
### Eklendi
- **İçerik türü filtresi** (filtre ekranı → "İçerik türü"): network yanıtları
  JSON/XML/HTML/Görsel/Metin/Diğer sınıflarına göre süzülebilir (seçiliyken yalnız o türler
  listelenir).
- **Görsel önizleme**: `image/*` yanıt gövdeleri `maxImageBodyBytes` (varsayılan 256 KB)
  sınırının altındaysa yakalanır ve detay ekranında önizlenir
  (`OlafNetworkConfiguration.maxImageBodyBytes`, `0` = kapalı).

## [0.39.0] — 2026-07-20
### Eklendi
- **Decode hatası yakalama**: `OlafDecoding.decode(_:from:url:)` (JSONDecoder sarmalayıcısı,
  hatayı aynen fırlatır) ve `Olaf.logDecodingError(_:url:data:typeName:)` — hatalı alanın tam
  yolu (`user.accounts[0].iban`) çıkarılır, ham gövdeyle birlikte `.decoding` kategorisine
  loglanır; detay ekranında "Decode Hatası" bölümü.

## [0.38.0] — 2026-07-20
### Eklendi
- **Postman Collection export** (⋯ → Paylaş → "Postman Collection"): görünen network
  istekleri Collection v2.1 olarak dışa aktarılır (aynı method+URL bir kez); Postman'e
  Import ile alınıp yeniden çalıştırılabilir.

## [0.37.0] — 2026-07-20
### Eklendi
- **İstatistik ekranı** (⋯ → İstatistikler): görünen network kayıtları için hata oranı,
  ortalama/medyan/p95 süre, toplam boyutlar, durum sınıfı ve metot dağılımı (bar'lı),
  en yavaş 5 istek ve en çok istek alan host'lar.

## [0.36.0] — 2026-07-20
### Eklendi
- **HAR export**: görünen network kayıtları HAR 1.2 belgesi olarak paylaşılabilir
  (Charles/Proxyman/Chrome DevTools doğrudan açar) — ⋯ → Paylaş → "HAR (network)".
  Zamanlama fazları (dns/connect/ssl/wait/receive) HAR timings'e eşlenir.

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

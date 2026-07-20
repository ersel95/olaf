# Bug-Reporter Mekanizması — Kaldırılan Kodun Özeti

> Bu döküman, Olaf paketinden **kaldırılan** "hataları backend'e bildiren" mekanizmanın
> (OlafUpload + OlafUI bug-report akışı) tam özetidir. Olaf artık yalnız network logger'dır.
> Bu mekanizma **ayrı bir projede** yeniden geliştirilecektir; döküman o geliştirmenin
> referansıdır. Kaldırılan kodun son hali git geçmişindedir: bu değişiklikten **önceki**
> commit'e bakın (`git log docs/bug-reporter-ozet.md` ile bu dökümanın eklendiği commit'in
> ebeveyni).

## 1. Genel akış (uçtan uca)

```
Kullanıcı ekran görüntüsü alır
  → ScreenshotDetector (userDidTakeScreenshotNotification) key window'u kendisi render eder
  → BugReportBanner ayrı bir UIWindow'da alttan "Paylaşmak ister misin?" balonu gösterir
  → [Evet] → BugReportSheet (form: "Ne yaşadın?" / "Ne olmalıydı?" / ilk seferde isim)
  → BugReportComposer: screenshot'ı JPEG'e sıkıştırır + cihaz kimliği + telemetri toplar
  → OlafBugReportService.sendReport: payload'ı kurar (log snapshot dahil)
  → OlafUploadQueue.submit → OlafUploader (multipart POST /reports)
  → Başarı: "Gönderildi" toast · Geçici hata: diske kuyruklanır, backoff ile tekrar denenir
```

İki **gate** (savunma katmanı):
1. **Local opt-in** (build-time): `OlafUpload.configure(enabled: true, apiKey:, baseURL:)`
   çağrılmadıkça hiçbir kod (remote config, detector, upload) çalışmaz. Varsayılan **kapalı**.
2. **Server-side kill-switch** (runtime): `GET /config` → `captureEnabled`. `false` ise banner
   hiç gösterilmez. **Fail-closed**: config çekilemezse `.disabled` varsayılır.

## 2. Modül haritası (kaldırılan dosyalar)

### `Sources/OlafUpload/` (tüm target)

| Dosya | Sorumluluk |
|---|---|
| `OlafUpload.swift` | Facade. `configure(enabled:apiKey:baseURL:environment:)` tek giriş noktası; idempotent. `StateBox` (NSLock) ile servis + detector-installer hook'u tutar. `setDetectorInstaller` ile UI katmanı UIKit bağımlılığı olmadan bağlanır (sıra bağımsız: configure önce de sonra da çağrılabilir). Recursion önleme: upload/config endpoint'lerini `OlafNetwork.excludedURLs`'e ekler. |
| `OlafUploadConfiguration.swift` | Config struct: `apiKey` (tek secret, `x-olaf-api-key` header'ı; backend app'i bundan tanır), `baseURL`, `environment`, `reportsPath` (`/api/v1/olaf/reports`), `configPath` (`/api/v1/olaf/config`), `requestTimeout` (30 sn), `maxRetryCount` (5), `baseRetryDelay` (5 sn), `screenshotJPEGQuality` (0.7), `maxScreenshotBytes` (4 MiB). `captureExclusionFragments`: host + iki path (capture'dan hariç tutulacaklar). Hiçbir gerçek URL/sır default olarak gömülmez. |
| `OlafBugReportService.swift` | Çalışma motoru. `bootstrap()`: remote config çek + kuyruğu boşalt. `isCaptureEnabled` (gate 2), `maxScreenshotBytes` = min(local, remote). `sendReport(whatHappened:whatExpected:testerName:screenshotJPEG:identity:telemetry:)`: payload kurar, `entries: Olaf.snapshot()` (TÜM kategoriler, ham LogEntry[]) ekler, kuyruk üzerinden gönderir. Tester adını Keychain'e kaydeder. |
| `OlafUploader.swift` | HTTP istemcisi. **Kendi ephemeral URLSession'ı, `protocolClasses = []`** → capture protokolü enjekte edilmez, recursion olmaz. Sonuç sınıflandırması: 2xx = success · 4xx = kalıcı hata (kuyruktan düş; **408/429 hariç** → geçici) · 5xx/ağ hatası = geçici (kuyrukla + backoff). `makeMultipartBody`: `report` part'ı `filename="report.json"` ile **dosya part'ı** olarak gönderilir (bazı multipart parser'lar text field'ı body'ye bağlamaz), `screenshot` part'ı `image/jpeg` binary. |
| `OlafUploadQueue.swift` | Offline kuyruk (`actor`). `Caches/Olaf/uploads/` altında zarf (`{id}.json`: boundary, attempt, createdAt, nextAttemptAt) + gövde (`{id}.body`) çifti. Yazım: `.atomic` + iOS'ta `.completeFileProtection`. Exponential backoff: `baseRetryDelay * 2^attempt`, en fazla `maxRetryCount` deneme. **TTL 48 saat**: bayat raporlar gönderilmeden silinir (hassas veri diskte süresiz kalmasın). `drain()` idempotent (`isDraining` bayrağı). Süreç yeniden başlasa da diskten devam eder. |
| `OlafRemoteConfig.swift` | `GET /config` yanıtı: `captureEnabled` (default **false**), `maxScreenshotBytes` (default 4 MiB). `OlafRemoteConfigClient` de kendi session'ını kullanır (protocolClasses boş). Hata → `.disabled`. |
| `OlafReportPayload.swift` | Veri sözleşmesi (aşağıda §3). |
| `OlafTelemetry.swift` | Anlık cihaz durumu toplayıcı + `OlafNetworkMonitor` (NWPathMonitor cache'i — wifi/cellular/wired/none). `prepare()`: pil izleme + network monitor'ü banner kurulurken erken başlatır ki ilk raporda dolu gelsin. Bellek: mach `task_vm_info.phys_footprint`. IP/SSID/konum toplanmaz. |
| `OlafDeviceIdentity.swift` | Kalıcı cihaz kimliği: **Keychain'de UUID** (uninstall'a dayanıklı; ilk üretim `identifierForVendor`, yoksa rastgele). Tester adı: **bir kerelik** sorulur, Keychain'de saklanır (`kSecAttrAccessibleAfterFirstUnlock`); eski UserDefaults değeri tek seferlik migre edilir. Cihaz meta: `utsname.machine` modeli (simülatörde `SIMULATOR_MODEL_IDENTIFIER`), OS sürümü, locale, ekran (nativeBounds). App meta: bundleId, `CFBundleShortVersionString`, `CFBundleVersion`. Minimal `KeychainStore` sarmalayıcısı (bağımlılıksız). |

### `Sources/OlafUI/Presentation/` (bug-report UI dosyaları)

| Dosya | Sorumluluk |
|---|---|
| `ScreenshotDetector.swift` | `userDidTakeScreenshotNotification` gözlemcisi. Sistem screenshot'ı app'e vermez → key window `UIGraphicsImageRenderer` + `drawHierarchy(afterScreenUpdates: true)` ile render edilir (**secure text field maskesi ancak böyle etkili olur** — gizli alanlar görüntüye sızmaz). Olaf'ın kendi pencereleri (`windowLevel >= .alert`) hariç tutulur. Sonuç `.olafScreenshotCaptured` notification'ı ile (UIImage object) yayınlanır. Ayrıca `Olaf.log(.info, "Ekran görüntüsü alındı", category: .screenshot)` ile timeline'a düşer. |
| `BugReportBanner.swift` | Orkestratör. Ayrı `UIWindow` (`windowLevel = .alert + 1`) + **PassthroughView** pattern'i: banner görünürken yalnız banner alanı dokunuş yakalar, gerisi alttaki app'e geçer (app etkileşilebilir kalır). 6 sn etkileşimsiz → otomatik kapanır. [Evet] → `BugReportSheet`'i `.formSheet` olarak present eder. `install()` sırasında `OlafTelemetry.prepare()` çağrılır. |
| `BugReportSheet.swift` | SwiftUI form. Alanlar: screenshot önizleme + **bilgilendirilmiş onay uyarısı** ("görüntü ekrandaki TÜM bilgileri içerir; hassas veri varsa göndermeyin"), ilk kullanımda isim, "Ne yaşadın?", "Ne olmalıydı?". UX: `@FocusState` alan sırası, klavye toolbar'ı ("Sonraki"/"Bitti"), odaklanan alanı klavye üstüne kaydırma (`ScrollViewReader`), gönderim sırasında `interactiveDismissDisabled`. Hata → inline banner + retry ("başarısız olursa kuyruğa alınır"). |
| `BugReportComposer.swift` | UI → servis köprüsü. JPEG encode: önce kalite düşürme (0.7 → 0.2, 0.15 adım), hâlâ büyükse **boyutu 0.7 çarpanıyla küçültme** (min 320pt) — `maxScreenshotBytes` altına inene dek. `OlafDeviceIdentity.current()` + `OlafTelemetry.capture()` MainActor'da toplanır. |
| `BugReportToast.swift` | "Gönderildi" toast'ı — ayrı geçici `UIWindow` (`alert + 2`), dokunuşa kapalı, 2 sn fade. |
| `OlafUI.swift` içindeki hook | `OlafUI.install()` → `OlafUpload.setDetectorInstaller { BugReportBanner.shared.install() }`. Kurulumu **çalıştırmaz**, yalnız hook verir; banner ancak host `configure(enabled: true)` yaptığında kurulur. |

### Diğer kaldırılanlar
- `Tests/OlafUploadTests/` — `ReportPayloadTests`, `RemoteConfigTests`, `OlafUploadConfigurationTests`, `MultipartBodyTests`, `OptInGateTests`.
- `LogCategory.screenshot` (OlafCore) — yalnız bu akış kullanıyordu.
- `Integration/OlafIntegration.swift` template'indeki OlafUpload bölümü (Info.plist/xcconfig anahtarları: `OLAF_BUG_REPORTER_ENABLED`, `OLAF_API_KEY`, `OLAF_API_BASE_URL`, `OLAF_ENVIRONMENT`).
- `INTEGRATION.md` §6 (bug-reporter kurulum/sorun giderme rehberi).

## 3. Veri sözleşmesi (backend API)

### `POST {baseURL}/api/v1/olaf/reports` — multipart/form-data
- Header: `x-olaf-api-key: <apiKey>` (auth + app tanıma; ayrıca appKey/slug taşınmaz).
- Part `report` (application/json, `filename="report.json"`):

```jsonc
{
  "app":    { "bundleId": "…", "version": "1.2.3", "build": "456", "environment": "staging" },
  "device": { "id": "<keychain-uuid>", "name": "Tester Adı|null", "model": "iPhone15,3",
              "osVersion": "17.4", "locale": "tr_TR", "screen": "1179x2556" },
  "report": { "whatHappened": "…", "whatExpected": "…",
              "capturedAt": "ISO-8601", "sessionId": "<Olaf.currentSessionID>" },
  "telemetry": {                       // opsiyonel; toplanamayan alan null (server'da jsonb)
    "timezone": "Europe/Istanbul", "screenScale": 3.0, "screenPoints": "390x844",
    "networkType": "wifi|cellular|wired|none|unknown",
    "batteryLevel": 87, "batteryState": "charging|full|unplugged|unknown",
    "lowPowerMode": false, "thermalState": "nominal|fair|serious|critical",
    "orientation": "portrait|…", "freeDiskBytes": 0, "totalDiskBytes": 0,
    "totalMemoryBytes": 0, "appMemoryBytes": 0
  },
  "entries": [ /* ham LogEntry[] — TÜM kategoriler, maskeleme yok */ ]
}
```

- Part `screenshot` (image/jpeg, `filename="screenshot.jpg"`) — opsiyonel.
- Encode: `JSONEncoder` + `.iso8601` tarih + `.withoutEscapingSlashes`.

### `GET {baseURL}/api/v1/olaf/config`
- Header: `x-olaf-api-key`. Yanıt: `{ "captureEnabled": bool, "maxScreenshotBytes": int }`.
- Alanlar decode'da opsiyonel; eksikse `captureEnabled=false`, `maxScreenshotBytes=4 MiB`.

## 4. Yeniden geliştirirken korunması gereken tasarım kararları

1. **Opt-in + fail-closed çift gate** — yanlışlıkla prod'da açılmaya karşı: local `enabled`
   (default false, xcconfig'ten) + server `captureEnabled` (config çekilemezse kapalı).
2. **Recursion önleme (iki güvence)** — uploader kendi session'ını kullanır (`protocolClasses=[]`)
   VE upload/config URL'leri network-capture exclude listesine eklenir.
3. **Offline dayanıklılık** — diske kalıcı kuyruk, exponential backoff, kalıcı/geçici hata ayrımı
   (4xx düşür ama 408/429 geçici), 48 saat TTL, `.completeFileProtection`.
4. **Screenshot güvenliği** — `drawHierarchy(afterScreenUpdates: true)` (secure field maskesi),
   kendi overlay pencerelerini render dışı bırak, sheet'te bilgilendirilmiş onay metni,
   boyut sınırına kadar kademeli JPEG sıkıştırma/küçültme.
5. **Kimlik** — cihaz UUID'si ve tester adı Keychain'de (reinstall'a dayanıklı); isim bir kez sorulur.
6. **UIKit'siz çekirdek + hook pattern** — upload katmanı UI'a bağımlı değil; UI, installer
   closure'ı kaydeder, configure başarılı olursa (sıra bağımsız) tetiklenir.
7. **Ayrı-pencere UI** — banner/toast/sheet app hiyerarşisine dokunmaz; passthrough hit-test ile
   app etkileşilebilir kalır.
8. **apiKey tek secret** — asla repoya gömülmez, xcconfig/Info.plist üzerinden host sağlar;
   baseURL secret değildir.
9. **Telemetri PII içermez** — IP/SSID/konum yok; yalnız cihaz-durumu alanları.

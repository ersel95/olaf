# Olaf — AI Agent Entegrasyon Talimatı

Bir AI agent "Olaf'u entegre et" komutu aldığında **bu dosyayı** takip eder. Adımlar mekanik ve sıralıdır.

## Ön koşullar
- Hedef: iOS 17+ uygulaması.
- Olaf paketi: `https://github.com/ersel95/olaf`
- Ürünler: `OlafCore` (motor) + `OlafUI` (viewer) zorunlu; `OlafNetwork` (ağ yakalama) ve `OlafUpload` (bug-reporter) opsiyonel.
- Dış tanılama araçları jenerik `ExternalToolBridge` ile host tarafında eklenebilir (paket hiçbir dış araca bağlı değildir).

## Adımlar

### 1. Paket bağımlılığını ekle
Xcode → Add Package → "Choose Package Products":
- Ana app target'ına: `OlafCore` **ve** `OlafUI` (zorunlu), ağ logları için `OlafNetwork`.
- App extension'lara (varsa): yalnız `OlafCore`.

### 2. Entegrasyon dosyasını kopyala (ZORUNLU)
`Integration/OlafIntegration.swift` dosyasını host app kaynaklarına kopyala (örn. `Core/Utils/`).
Tek entegrasyon noktasıdır: `OlafManager` (başlatma + loglama).
`// ADAPT:` satırlarını uyarla:
- Gating: `#if !PROD` (önerilen — capture kodu prod binary'sine girmez) veya runtime feature flag.
- Log kategorilerini projeye göre düzenle.

> Uygulama **`Olaf`'a doğrudan bağlanmaz**; loglar manager üzerinden atılır:
> `OlafManager.shared.info("...", category: .auth)`, `OlafManager.shared.error(error, category: .payment)`.
> Olaf başlatılmamışsa (PROD) çağrılar no-op'tur.

### 3. Başlatmayı bağla
App giriş noktasında — **paylaşılan URLSession kurulmadan ÖNCE** (SwiftUI `App.init` veya
`AppDelegate.didFinishLaunching` başı, session preload'undan önce):
```swift
OlafManager.shared.initialize()
```

### 4. Özel Alamofire/URLSession session'ı varsa
Host kendi `URLSessionConfiguration`'ını kuruyorsa (otomatik swizzle yerine deterministik enjeksiyon):
session kurulurken tek satır:
```swift
OlafManager.shared.configureNetworkCapture(configuration)
```

### 5. Doğrula
- Derle. Cihazı salla → Olaf viewer açılır.

## Loglama (app her zaman manager üzerinden loglar)
Uygulama kodunda `import OlafCore` + `Olaf.x(...)` KULLANMA. Manager'ı kullan:
```swift
OlafManager.shared.info("Login başarılı", category: .auth)
OlafManager.shared.error(error, category: .payment)
```
Manager `trace/debug/info/notice/warning/error/critical` + `error(Error)` sağlar; çağıran dosya/satır korunur.
`print()` çağrılarını kademeli olarak bu metodlara taşı.

### Kategorileri genişletme
Entegrasyon dosyasındaki `extension LogCategory` bloğuna projenin modüllerini ekle:
```swift
public extension LogCategory {
    static let cards: LogCategory = "cards"
    static let transfers: LogCategory = "transfers"
}
```
Dosya `@_exported import OlafCore` içerdiğinden çağrı yerleri `import OlafCore` yazmadan kullanabilir.

## Davranış kuralları (agent için)
- Paketin `Sources/` içeriğini DEĞİŞTİRME; entegrasyon host tarafındadır (yalnız template + ürün seçimi).
- `initialize(...)` paylaşılan session'dan ÖNCE çağrılmalı; aksi halde ilk istekler yakalanmayabilir.
- `Olaf.start(...)` / `initialize(...)` yalnız bir kez çağrılır.
- Gating'i `#if DEBUG`'a bağlama (TestFlight UAT release config). `#if !PROD` veya runtime flag kullan.

## (Opsiyonel) Network loglarını listele — `OlafNetwork`
`OlafNetwork` ürününü ekle. **En kolay (networking koduna dokunmadan):** `initialize` içinde zaten çağrılan
```swift
OlafNetwork.startAutomaticCapture()   // URLSessionConfiguration swizzle + global; SSL kırmaz
```
İstek/yanıtlar `.network` kategorisinde ham (maskelemesiz) Olaf'a düşer. Gövde + header **default açık**;
kısmak için `startAutomaticCapture(OlafNetworkConfiguration(capturesBodies: false))`.
Kendi session'ına manuel/deterministik enjekte için (adım 4) `configureNetworkCapture(_:)` / `install(into:chainingTo:)`.

## (Opsiyonel) Bug-reporter — screenshot → banner → upload (`OlafUpload`)
**OPT-IN, varsayılan KAPALI.** Detaylı adımlar: `INTEGRATION.md` §6–§8.
1. `OlafUpload` ürününü ana app target'ına ekle.
2. `initialize()` template'i opt-in `OlafUpload.configure(enabled:apiKey:baseURL:environment:)`'ı
   zaten içerir (hepsi `#if !PROD`). Değerleri **host xcconfig → Info.plist** ile sağla — **repoya commit ETME** (public repo).
   `enabled` default `false`; açmak için `OLAF_BUG_REPORTER_ENABLED = true`.
3. Navigation breadcrumb için host'ta `OlafNavigationObserver` adapter'ı (Coordinator) ekle veya manuel
   `Olaf.trackScreen("Ekran", kind: "push")` çağır (INTEGRATION.md §7). Olaf, Coordinator'a import ETMEZ.
4. Üç gate: local `enabled` → `#if !PROD` → server-side `captureEnabled` (`GET /config`). Hiçbiri açık değilse sıfır ağ aktivitesi.

## Genişletme: dış bir tanılama aracı eklemek
Jenerik geçiş için `ExternalToolBridge`'e uyan bir tip yazıp host'ta kaydet:
```swift
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, ya da OlafUI.presentExternal { ... } */ }
}
OlafUI.register(SomeToolBridge())
```

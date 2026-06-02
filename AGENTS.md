# LogFox — AI Agent Entegrasyon Talimatı

Bir AI agent "LogFox'u entegre et" komutu aldığında **bu dosyayı** takip eder. Adımlar mekanik ve sıralıdır.

## Ön koşullar
- Hedef: iOS 17+ uygulaması.
- LogFox paketi: `https://github.com/ersel95/logfox`
- Ürünler: `LogFoxCore` (motor) + `LogFoxUI` (viewer) zorunlu; `LogFoxNetwork` (ağ yakalama) opsiyonel.
- Dış tanılama araçları jenerik `ExternalToolBridge` ile host tarafında eklenebilir (paket hiçbir dış araca bağlı değildir).

## Adımlar

### 1. Paket bağımlılığını ekle
Xcode → Add Package → "Choose Package Products":
- Ana app target'ına: `LogFoxCore` **ve** `LogFoxUI` (zorunlu), ağ logları için `LogFoxNetwork`.
- App extension'lara (varsa): yalnız `LogFoxCore`.

### 2. Entegrasyon dosyasını kopyala (ZORUNLU)
`Integration/LogFoxIntegration.swift` dosyasını host app kaynaklarına kopyala (örn. `Core/Utils/`).
Tek entegrasyon noktasıdır: `LogFoxManager` (başlatma + loglama).
`// ADAPT:` satırlarını uyarla:
- Gating: `#if !PROD` (önerilen — capture kodu prod binary'sine girmez) veya runtime feature flag.
- Log kategorilerini projeye göre düzenle.

> Uygulama **`LogFox`'a doğrudan bağlanmaz**; loglar manager üzerinden atılır:
> `LogFoxManager.shared.info("...", category: .auth)`, `LogFoxManager.shared.error(error, category: .payment)`.
> LogFox başlatılmamışsa (PROD) çağrılar no-op'tur.

### 3. Başlatmayı bağla
App giriş noktasında — **paylaşılan URLSession kurulmadan ÖNCE** (SwiftUI `App.init` veya
`AppDelegate.didFinishLaunching` başı, session preload'undan önce):
```swift
LogFoxManager.shared.initialize()
```

### 4. Özel Alamofire/URLSession session'ı varsa
Host kendi `URLSessionConfiguration`'ını kuruyorsa (otomatik swizzle yerine deterministik enjeksiyon):
session kurulurken tek satır:
```swift
LogFoxManager.shared.configureNetworkCapture(configuration)
```

### 5. Doğrula
- Derle. Cihazı salla → LogFox viewer açılır.

## Loglama (app her zaman manager üzerinden loglar)
Uygulama kodunda `import LogFoxCore` + `LogFox.x(...)` KULLANMA. Manager'ı kullan:
```swift
LogFoxManager.shared.info("Login başarılı", category: .auth)
LogFoxManager.shared.error(error, category: .payment)
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
Dosya `@_exported import LogFoxCore` içerdiğinden çağrı yerleri `import LogFoxCore` yazmadan kullanabilir.

## Davranış kuralları (agent için)
- Paketin `Sources/` içeriğini DEĞİŞTİRME; entegrasyon host tarafındadır (yalnız template + ürün seçimi).
- `initialize(...)` paylaşılan session'dan ÖNCE çağrılmalı; aksi halde ilk istekler yakalanmayabilir.
- `LogFox.start(...)` / `initialize(...)` yalnız bir kez çağrılır.
- Gating'i `#if DEBUG`'a bağlama (TestFlight UAT release config). `#if !PROD` veya runtime flag kullan.

## (Opsiyonel) Network loglarını listele — `LogFoxNetwork`
`LogFoxNetwork` ürününü ekle. **En kolay (networking koduna dokunmadan):** `initialize` içinde zaten çağrılan
```swift
LogFoxNetwork.startAutomaticCapture()   // URLSessionConfiguration swizzle + global; SSL kırmaz
```
İstek/yanıtlar `.network` kategorisinde redaksiyonla LogFox'a düşer. Gövde + header **default açık**;
kısmak için `startAutomaticCapture(LogFoxNetworkConfiguration(capturesBodies: false))`.
Kendi session'ına manuel/deterministik enjekte için (adım 4) `configureNetworkCapture(_:)` / `install(into:chainingTo:)`.

## Genişletme: dış bir tanılama aracı eklemek
Jenerik geçiş için `ExternalToolBridge`'e uyan bir tip yazıp host'ta kaydet:
```swift
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, ya da LogFoxUI.presentExternal { ... } */ }
}
LogFoxUI.register(SomeToolBridge())
```

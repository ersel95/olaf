# LogFox — AI Agent Entegrasyon Talimatı

Bir AI agent "LogFox'u entegre et" komutu aldığında **bu dosyayı** takip eder. Adımlar mekanik ve sıralıdır.

## Ön koşullar
- Hedef: iOS 17+ uygulaması.
- LogFox paketi: `https://github.com/ersel95/logfox` (ürünler: `LogFoxCore`, `LogFoxUI`).
- Bu paket Netfox/Pulse'a **bağlı değildir**; bunlara geçiş host tarafında, `#if canImport` ile opsiyoneldir.

## Adımlar

### 1. Paket bağımlılığını ekle
`Package.swift` (SPM projeleri) veya Xcode → Add Package:
- Ana app target'ına: `LogFoxCore` **ve** `LogFoxUI`.
- App extension'lara (varsa): yalnız `LogFoxCore`.

### 2. Entegrasyon dosyasını kopyala (ZORUNLU)
`Integration/LogFoxIntegration.swift` dosyasını host app kaynaklarına **mutlaka** kopyala (örn. `Core/Utils/`).
Bu dosya tek entegrasyon noktasıdır: `LogFoxManager` (başlatma + **loglama fonksiyonları**) + `LogFoxNetworkLogger`
enum'u + (canImport-gate'li) `NetfoxBridge` & `PulseBridge`.
`// ADAPT:` ile işaretli satırları projeye uyarla:
- Feature-flag kontrolü (varsa). Yoksa satırı kaldır.
- `#if !PROD` derleme koşulu projede yoksa, projenin eşdeğer koşuluyla değiştir veya kaldır.

> Uygulama **`LogFox`'a doğrudan bağlanmaz**; loglar bu manager üzerinden atılır:
> `LogFoxManager.shared.info("...", category: .auth)`, `LogFoxManager.shared.error(error, category: .payment)`.
> Manager `trace/debug/info/notice/warning/error/critical` + `error(Error)` sağlar; çağıran dosya/satır korunur.
> LogFox başlatılmamışsa (PROD) çağrılar no-op'tur → her yerde güvenle çağrılabilir.

### 3. Başlatmayı bağla
Bir projede **yalnız bir** network logger aktiftir. Önce projede hangisinin kullanıldığını tespit et
(`NFX`/`netfox` import'u → `.netfox`; `Pulse`/`PulseUI` import'u → `.pulse`; ikisi de yoksa → `.none`).
App giriş noktasında (SwiftUI `App.init` veya `AppDelegate.didFinishLaunching`), mevcut başlatmaların yanına:
```swift
LogFoxManager.shared.initialize(networkLogger: .netfox)   // .netfox / .pulse / .none
```
Seçilen araç link'li değilse `canImport` köprüyü atlar (hata olmaz, sadece geçiş butonu görünmez).

### 4. Netfox kullanılıyorsa: shake'i LogFox'a devret
Projede Netfox başlatılan yeri bul (`NFX.sharedInstance().start()`), hemen ardına ekle:
```swift
NFX.sharedInstance().setGesture(.custom)   // shake artık LogFox'un
```
> Pulse'ın shake davranışı yoktur; ek işlem gerekmez.

### 5. Doğrula
- Derle. Hata yoksa: cihazı salla → LogFox viewer açılır.
- Viewer toolbar (•••) menüsünde, **seçilen ve link'li** tek network logger buton olarak görünür ("Netfox" veya "Pulse").
- Netfox butonu → LogFox kapanır, Netfox açılır. Pulse butonu → Pulse konsolu LogFox üzerinde açılır.

## Loglama (app her zaman manager üzerinden loglar)
Uygulama kodunda `import LogFoxCore` + `LogFox.x(...)` KULLANMA. Entegrasyon dosyasındaki manager'ı kullan:
```swift
LogFoxManager.shared.info("Login başarılı", category: .auth)
LogFoxManager.shared.error(error, category: .payment)
```
Manager `trace/debug/info/notice/warning/error/critical` + `error(Error)` sağlar; çağıran dosya/satır korunur,
LogFox başlatılmamışsa (PROD) no-op'tur. `print()` çağrılarını kademeli olarak bu metodlara taşı.

### Kategorileri genişletme
`LogCategory` string-backed'tir; entegrasyon dosyasındaki `extension LogCategory` bloğuna projenin modüllerini ekle:
```swift
public extension LogCategory {
    static let cards: LogCategory = "cards"
    static let transfers: LogCategory = "transfers"
}
```
Entegrasyon dosyası `@_exported import LogFoxCore` içerdiğinden, çağrı yerleri `import LogFoxCore` yazmadan
`LogFoxManager.shared.info("...", category: .cards)` kullanabilir.

## Davranış kuralları (agent için)
- Paketin `Sources/` içeriğini DEĞİŞTİRME; entegrasyon tamamen host tarafındadır.
- `#if canImport(netfox)` / `#if canImport(PulseUI)` kontrollerini **host dosyasında** tut — pakete taşıma (pakette her zaman false döner).
- Netfox modül import adı SPM'de `netfox`, Pulse'ta network/log için `Pulse`, UI için `PulseUI`'dir. Projedeki gerçek import adına göre `canImport` koşulunu doğrula.
- `LogFox.start(...)` yalnız bir kez çağrılır (idempotent ama gereksiz tekrar etme).
- Gating'i `#if DEBUG`'a bağlama — TestFlight UAT/Prod config'te olur. Runtime feature flag kullan.

## (Opsiyonel) Network loglarını LogFox'ta listele — `LogFoxNetwork`
İstenirse `LogFoxNetwork` ürününü ana app target'ına ekle. Sonra app'in URLSession/Alamofire
`URLSessionConfiguration`'ının kurulduğu yeri bul (YapiKredi'de `BaseService`, `NFXProtocol`
enjeksiyonunun yanı) ve ekle:
```swift
import LogFoxNetwork
LogFoxNetwork.install(into: configuration)   // veya LogFoxNetwork.installGlobally()
```
İstek/yanıtlar `.network` kategorisinde, redaksiyondan geçerek LogFox'a düşer. Gövde + header
yakalama **default açık**; kısmak istersen init'te ver: `install(into: config, with: LogFoxNetworkConfiguration(capturesBodies: false))`.

## Genişletme: yeni bir araç eklemek
Herhangi bir tanılama aracına geçiş, `ExternalToolBridge`'e uyan bir tip + host'ta `canImport` ile eklenir:
```swift
#if canImport(SomeTool)
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, ya da LogFoxUI.presentExternal { ... } */ }
}
#endif
```

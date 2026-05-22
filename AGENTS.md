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

### 2. Entegrasyon dosyasını kopyala
`Integration/LogFoxIntegration.swift` dosyasını host app kaynaklarına kopyala (örn. `Core/Utils/`).
Bu dosya: `LogFoxManager` + `LogFoxToolsConfig` + (canImport-gate'li) `NetfoxBridge` & `PulseBridge` içerir.
`// ADAPT:` ile işaretli satırları projeye uyarla:
- Feature-flag kontrolü (varsa). Yoksa satırı kaldır.
- `#if !PROD` derleme koşulu projede yoksa, projenin eşdeğer koşuluyla değiştir veya kaldır.

### 3. Başlatmayı bağla
App giriş noktasında (SwiftUI `App.init` veya `AppDelegate.didFinishLaunching`), mevcut başlatmaların yanına:
```swift
LogFoxManager.shared.initialize(
    tools: LogFoxToolsConfig(enableNetfox: true, enablePulse: true)
)
```
`enableNetfox` / `enablePulse` = host'un o araca geçişe izin verip vermediği. İlgili modül link'li değilse `canImport` zaten köprüyü atlar (flag etkisiz olur, hata olmaz).

### 4. Netfox kullanılıyorsa: shake'i LogFox'a devret
Projede Netfox başlatılan yeri bul (`NFX.sharedInstance().start()`), hemen ardına ekle:
```swift
NFX.sharedInstance().setGesture(.custom)   // shake artık LogFox'un
```
> Pulse'ın shake davranışı yoktur; ek işlem gerekmez.

### 5. Doğrula
- Derle. Hata yoksa: cihazı salla → LogFox viewer açılır.
- Viewer toolbar (•••) menüsünde, **yalnız link'li ve etkin** araçlar buton olarak görünür ("Netfox", "Pulse").
- Netfox butonu → LogFox kapanır, Netfox açılır. Pulse butonu → Pulse konsolu LogFox üzerinde açılır.

## Davranış kuralları (agent için)
- Paketin `Sources/` içeriğini DEĞİŞTİRME; entegrasyon tamamen host tarafındadır.
- `#if canImport(netfox)` / `#if canImport(PulseUI)` kontrollerini **host dosyasında** tut — pakete taşıma (pakette her zaman false döner).
- Netfox modül import adı SPM'de `netfox`, Pulse'ta network/log için `Pulse`, UI için `PulseUI`'dir. Projedeki gerçek import adına göre `canImport` koşulunu doğrula.
- `LogFox.start(...)` yalnız bir kez çağrılır (idempotent ama gereksiz tekrar etme).
- Gating'i `#if DEBUG`'a bağlama — TestFlight UAT/Prod config'te olur. Runtime feature flag kullan.

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

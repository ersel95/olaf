# ``Olaf``

Uygulama + network loglarını cihazda görüntüleyip paylaşmayı sağlayan, tamamen local Swift
network logger'ı. Backend yoktur; hiçbir veri ağ üzerinden gönderilmez.

## Overview

Olaf üç parçadan oluşan tek bir modüldür:

- **Core** — `Olaf` facade'ı: ring buffer, NDJSON disk persistansı (oturumlar arası geçmiş),
  OSLog köprüsü, start-öncesi log tamponlama. UIKit'siz; her platformda derlenir.
- **Network** — `OlafNetwork.startAutomaticCapture()`: URLSessionConfiguration swizzle ile tüm
  session'ların istek/yanıtlarını (gövde/header/zamanlama dahil) `.network` kategorisinde yakalar.
  Paylaşılan tek proxy session kullanır; TLS doğrulaması sistemde kalır (SSL kırılmaz).
- **UI** — `OlafUI.install()`: shake → SwiftUI viewer (Oturum/Geçmiş, filtre, arama, aktif
  istekler barı, paylaşım: .log / NDJSON / cURL).

Tüm veri **ham** saklanır ve gösterilir (maskeleme yoktur) → yalnız non-prod debug'da çalıştırın
(`#if !PROD`).

```swift
// Uygulama başlangıcında (paylaşılan URLSession kurulmadan ÖNCE):
Olaf.start(.default)
OlafNetwork.startAutomaticCapture()
Task { @MainActor in OlafUI.install() }

// Loglama:
Olaf.info("Login başarılı", category: .auth, metadata: ["method": "biometric"])
```

## Topics

### Başlarken

- ``Olaf/start(_:)``
- ``OlafConfiguration``
- ``OlafUI``

### Loglama

- ``LogLevel``
- ``LogCategory``
- ``LogEntry``

### Network yakalama

- ``OlafNetwork``
- ``OlafNetworkConfiguration``
- ``PendingNetworkRequest``

### Okuma ve dışa aktarma

- ``Olaf/snapshot()``
- ``Olaf/loadPersistedEntries()``
- ``Olaf/stream()``
- ``Olaf/exportFileURL(entries:)``
- ``Olaf/exportNDJSONFileURL(entries:)``
- ``Olaf/importOSLogEntries(since:category:excludingSubsystems:)``

### Viewer genişletme

- ``ExternalToolBridge``

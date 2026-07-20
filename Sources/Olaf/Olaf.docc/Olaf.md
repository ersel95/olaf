# ``Olaf``

A fully local Swift network logger that lets you view and share app + network logs on-device.
There is no backend; no data is ever sent over the network.

## Overview

Olaf is a single module made up of three parts:

- **Core** — the `Olaf` facade: ring buffer, NDJSON disk persistence (history across sessions),
  OSLog bridge, pre-start log buffering. UIKit-free; compiles on every platform.
- **Network** — `OlafNetwork.startAutomaticCapture()`: captures every session's requests/responses
  (including body/header/timing) in the `.network` category, via a URLSessionConfiguration swizzle.
  Uses a single shared proxy session; TLS validation stays with the system (SSL is not broken).
- **UI** — `OlafUI.install()`: shake → SwiftUI viewer (Session/History, filter, search, active
  requests bar, sharing: .log / NDJSON / cURL).

All data is stored and displayed **raw** (there is no masking) → run this only in non-prod debug
builds (`#if !PROD`).

```swift
// At app startup (BEFORE the shared URLSession is set up):
Olaf.start(.default)
OlafNetwork.startAutomaticCapture()
Task { @MainActor in OlafUI.install() }

// Logging:
Olaf.info("Login succeeded", category: .auth, metadata: ["method": "biometric"])
```

## Topics

### Getting started

- ``Olaf/start(_:)``
- ``OlafConfiguration``
- ``OlafUI``

### Logging

- ``LogLevel``
- ``LogCategory``
- ``LogEntry``

### Network capture

- ``OlafNetwork``
- ``OlafNetworkConfiguration``
- ``PendingNetworkRequest``

### Reading and exporting

- ``Olaf/snapshot()``
- ``Olaf/loadPersistedEntries()``
- ``Olaf/stream()``
- ``Olaf/exportFileURL(entries:)``
- ``Olaf/exportNDJSONFileURL(entries:)``
- ``Olaf/importOSLogEntries(since:category:excludingSubsystems:)``

### Extending the viewer

- ``ExternalToolBridge``

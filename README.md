<p align="center">
  <img src="docs/olaf-logo.png" alt="Olaf" width="140">
</p>

<h1 align="center">Olaf</h1>

<p align="center">
  <b>On-device network logger &amp; log viewer for iOS and Android.</b><br>
  Shake your device — see every request, response, and log. Nothing ever leaves the device.
</p>

<p align="center">
  <a href="https://github.com/ersel95/olaf/actions/workflows/ci.yml"><img src="https://github.com/ersel95/olaf/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/ersel95/olaf/releases"><img src="https://img.shields.io/github/v/tag/ersel95/olaf?filter=!android-*&label=iOS&color=blue" alt="iOS release"></a>
  <a href="https://github.com/ersel95/olaf/releases"><img src="https://img.shields.io/github/v/tag/ersel95/olaf?filter=android-*&label=Android&color=green" alt="Android release"></a>
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-blue.svg" alt="iOS 17+">
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="Swift Package Manager">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey.svg" alt="MIT License"></a>
</p>

> **Olaf is not a network proxy and not a crash reporter.** It has **no backend, no telemetry,
> and zero dependencies**. Logs are stored on-device as NDJSON and shared only when *you* tap
> share. It also does **not** redact anything — data is shown raw, which is exactly why it is
> a **non-production debug tool** (`#if !PROD`).

## Two platforms, one repository

| | Lives in | Install | Docs |
|---|---|---|---|
| **iOS** (Swift, SwiftUI) | repository root | Swift Package Manager — see [below](#installation) | this file · [INTEGRATION](INTEGRATION.md) · [AGENTS](AGENTS.md) |
| **Android** (Kotlin, Compose) | [`Android/`](Android/) | JitPack — see [Android/README](Android/README.md#quick-start) | [Android/README](Android/README.md) · [INTEGRATION](Android/INTEGRATION.md) · [AGENTS](Android/AGENTS.md) |

Both are actively maintained and ship on **independent version lines** (`0.51.0` for iOS,
`android-0.10.0` for Android), so a release on one never forces one on the other — see
[RELEASING.md](RELEASING.md). They share the product decisions, the on-disk NDJSON schema and the
network metadata keys, so the same tooling reads either platform's export.

The Swift package stays at the repository root, so Swift Package Manager resolution is unaffected
by the Android sources; `android-*` tags are not semver, so SPM ignores them.

**The rest of this file documents the iOS package.** For Android, start at
**[Android/README.md](Android/README.md)**.

<!-- TODO: add a demo GIF here — shake → viewer → request detail (docs/demo.gif) -->

## Features

Both platforms carry the same feature set unless marked otherwise.

- [x] **App + network logs in a single timeline** — categories, levels, call-site info, live stream
- [x] **Shake → viewer** — search, filters, session/history scopes, paginated history, pin & multi-select
- [x] **Request detail** — status banner, collapsible sections, headers, syntax-highlighted bodies, image previews, cURL
- [x] **Timing breakdown** — DNS / TCP / TLS / TTFB per request, protocol (h2/h3), connection reuse ("is the API slow, or the network?")
- [x] **Active requests bar** — in-flight calls shown live with elapsed time; spot a hung request instantly
- [x] **Response mocking** — your own status/body/delay/transport-error without hitting the network; convert any captured response into a mock **on-device, no code**
- [x] **Decoding-error capture** — logs the exact failing field path (`user.accounts[0].iban`) next to the raw body, folded into the request it belongs to
- [x] **Statistics** — error rate, avg/median/p95 durations, status & method distribution, slowest requests
- [x] **Export anywhere** — `.log`, raw NDJSON, **HAR 1.2** (Charles/Proxyman/DevTools), **Postman Collection v2.1**
- [x] **History across launches** — NDJSON persistence with rotation and retention
- [x] **Bridges** — a logging-backend template (swift-log on iOS, Timber on Android), system-log import (OSLog / Logcat), and a generic `ExternalToolBridge` to hand off to your own tool
- [x] *iOS:* **zero-code capture** — `startAutomaticCapture()` hooks every `URLSession` (Alamofire included) without touching your networking code
- [x] *Android:* **capture notification & launcher shortcut**, no-op release artifact, its own task for split-screen use

## Quick Start

**iOS** — at app startup, before your shared `URLSession` is created (wrap in `#if !PROD`):

```swift
import Olaf

Olaf.start(.default)                        // engine: disk + OSLog mirror
OlafNetwork.startAutomaticCapture()         // capture all network traffic
Task { @MainActor in OlafUI.install() }     // shake → viewer

Olaf.info("Login succeeded", category: .auth, metadata: ["method": "biometric"])
Olaf.error(error, category: .payment)
```

**Android** — in `Application.onCreate`, before your shared `OkHttpClient` is built:

```kotlin
Olaf.start(this)
OlafUI.install(this)          // shake → viewer

// where the client is built:
OkHttpClient.Builder().installOlaf().build()   // capture + timing

Olaf.info("Login succeeded", LogCategory.Auth, mapOf("method" to "biometric"))
Olaf.error(throwable, LogCategory.Payment)
Olaf.debug { "Parsed ${items.size} items" }    // never built when below the threshold
```

Then shake the device — <kbd>⌃⌘Z</kbd> in the iOS simulator, `adb emu sensor set acceleration 0:0:50`
on an Android emulator — and the viewer opens.

## Installation

**iOS** — Xcode → **File → Add Package Dependencies…**

```
https://github.com/ersel95/olaf.git
```

or in `Package.swift`:

```swift
.package(url: "https://github.com/ersel95/olaf.git", from: "0.50.0")
```

Single product: `Olaf` — engine + network capture + viewer, one `import Olaf`.

**Android** — the artifacts are built from the git tag by JitPack:

```kotlin
// settings.gradle.kts
maven { url = uri("https://jitpack.io") }
```

```kotlin
// build.gradle.kts of the module that owns your OkHttpClient
debugImplementation("com.github.ersel95.olaf:olaf:android-0.10.0")
releaseImplementation("com.github.ersel95.olaf:olaf-no-op:android-0.10.0")
```

The release artifact keeps the same API with empty bodies, so no capture code, no viewer and no
stored logs reach a production APK.

> For a production-grade setup (an `OlafManager` facade, build gating, category conventions), copy
> the drop-in template and follow **[INTEGRATION.md](INTEGRATION.md)** (iOS) or
> **[Android/INTEGRATION.md](Android/INTEGRATION.md)**. AI agents follow **[AGENTS.md](AGENTS.md)** /
> **[Android/AGENTS.md](Android/AGENTS.md)**.

## Requirements

| Platform | Language | Toolchain | Dependencies |
|---|---|---|---|
| iOS 17+ (viewer) · macOS 14+ (engine, tests) | Swift 5.9+ | Xcode 15+ | **None** |
| Android, minSdk 26 · compileSdk 36 | Kotlin 2.1+ | Java 17 | OkHttp, Compose (UI/Material3), Coroutines |

No Hilt, no Room, no reflection, no annotation processing on either side.

## Network capture

**iOS** — one line, no changes to your networking code:

```swift
OlafNetwork.startAutomaticCapture(OlafNetworkConfiguration(
    includedURLs: ["api-gateway"],                            // only your API (empty = all)
    excludedURLs: ["firebaseio", "crashlytics", "googleapis"] // hide SDK noise
))
```

Requests are re-sent through a single shared proxy session (connection pool & cookies preserved),
logged **raw**, and validated with **system TLS** — pinning and the OS trust chain are never bypassed.

**Android** — an interceptor on your client:

```kotlin
OlafNetwork.configuration = OlafNetworkConfiguration(
    includedUrls = listOf("api-gateway"),
    excludedUrls = listOf("firebaseio", "crashlytics", "googleapis")
)

OkHttpClient.Builder()
    .addInterceptor(OlafNetwork.interceptor())
    .eventListenerFactory(OlafNetwork.eventListenerFactory())   // timing breakdown
    .build()
```

OkHttp has no global injection point, so the interceptor is added explicitly — the same single line
Chucker needs. In exchange nothing re-issues your requests, so your TLS, pinning and timeouts apply
untouched.

### Response mocking

```swift
// iOS
OlafNetwork.addMock(OlafMockResponse(urlContains: "/v1/accounts", json: #"{"accounts": []}"#))
OlafNetwork.addMock(.failure(urlContains: "/v1/rates", error: .timedOut, delaySeconds: 3))
```

```kotlin
// Android
OlafNetwork.addMock(OlafMockResponse(urlContains = "/v1/accounts", json = "{\"accounts\": []}"))
OlafNetwork.addMock(OlafMockResponse.failure("/v1/rates", OlafMockResponse.TransportError.Timeout))
```

Or entirely on-device on both platforms: open any captured request → **Convert to Mock** → edit
status/body/delay → save. Manage active mocks from the viewer's overflow menu.

<details>
<summary><b>Known limitations</b></summary>

**iOS** (inherent to `URLProtocol` capture)

- WebSocket (`URLSessionWebSocketTask`) and background-session traffic are not captured — URLSession doesn't route them through `URLProtocol`.
- `uploadTask(fromFile:)` bodies are not captured; `httpBody`/`httpBodyStream` bodies are (the stream is read into RAM — prefer `capturesBodies: false` for very large uploads).
- Session-level settings of the host session (`waitsForConnectivity`, `allowsCellularAccess`, …) are not carried over; the request's own `timeoutInterval` is.
- If the host enforces custom certificate pinning, the proxy may not pass that traffic — system validation applies, by design.

**Android** (inherent to interceptor-based capture)

- No zero-code capture: the interceptor must be added to each `OkHttpClient` you want captured.
- OkHttp allows a single `EventListener.Factory` per client; if the app already installs one, use `installOlaf(withTiming = false)` and lose only the timing section.
- WebSocket traffic is not captured.
- Brotli bodies need OkHttp's `BrotliInterceptor` installed after Olaf's; gzip is handled transparently.

</details>

<details>
<summary><b>Architecture</b></summary>

Same shape on both platforms — a facade over a runtime that owns a single-writer store:

```
Olaf (facade)
  └─ OlafRuntime            # lifecycle, kill switch, level threshold, pre-start buffer
       └─ LogStore          # serial queue / single writer thread:
            │                 ring buffer → disk → system log → live stream
            ├─ FilePersistence   # NDJSON, size-based rotation + retention
            ├─ LogFormatter      # plain text / NDJSON export
            └─ OSLogMirror / LogcatMirror

iOS      OlafNetwork (URLProtocol) ── OlafProxySession   ·  OlafUI → separate UIWindow
Android  OlafNetwork (Interceptor + EventListener)       ·  OlafUI → its own Activity & task
```

- **Messages below the threshold are never built** — `@autoclosure` on iOS, a lambda overload on Android.
- **The engine is UI-free**: it builds and tests without UIKit on iOS and without Compose on Android.
- **The on-disk NDJSON schema is identical**, so the same `jq`/tooling reads either platform's export.

</details>

## Privacy & Security

- **Fully local.** No backend, no analytics, no network calls of its own. Data leaves the device only through the share sheet, by explicit user action.
- **No redaction, by design.** Everything is stored raw (including `Authorization`/`Cookie`); that's what makes it useful for debugging — and why you must gate it out of production builds.
- *iOS:* ships a [`PrivacyInfo.xcprivacy`](Sources/Olaf/PrivacyInfo.xcprivacy) manifest (no tracking, no data collection).\n- *Android:* the `FileProvider` is declared by the library itself and exposes only the export directory; release builds link the no-op artifact, so none of this reaches production.

## Development

```bash
# iOS
swift build && swift test                                          # macOS
xcodebuild -scheme Olaf -destination 'generic/platform=iOS' build   # iOS verification

# Android
cd Android
./gradlew :olaf:testDebugUnitTest
./gradlew :olaf:assembleRelease :olaf-no-op:assembleRelease
./gradlew :sample:assembleDebug :sample:assembleRelease   # API compatibility of both artifacts
./gradlew :sample:installDebug                            # try it on a device/emulator
```

107 tests on iOS, 108 on Android; zero warnings on both. See the [iOS CHANGELOG](CHANGELOG.md) and
the [Android CHANGELOG](Android/CHANGELOG.md).

## Releasing

Both platforms ship from this repository on independent, tag-driven version lines
(`0.51.0` for iOS, `android-0.9.0` for Android) — see **[RELEASING.md](RELEASING.md)**.

## License

MIT — see [LICENSE](LICENSE).

<p align="center">
  <img src="docs/olaf-logo.png" alt="Olaf" width="140">
</p>

<h1 align="center">Olaf</h1>

<p align="center">
  <b>On-device network logger &amp; log viewer for iOS.</b><br>
  Shake your device — see every request, response, and log. Nothing ever leaves the device.
</p>

<p align="center">
  <a href="https://github.com/ersel95/olaf/actions/workflows/ci.yml"><img src="https://github.com/ersel95/olaf/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/ersel95/olaf/tags"><img src="https://img.shields.io/github/v/tag/ersel95/olaf?label=release&color=blue" alt="Release"></a>
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-blue.svg" alt="iOS 17+">
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="Swift Package Manager">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey.svg" alt="MIT License"></a>
</p>

> **Olaf is not a network proxy and not a crash reporter.** It has **no backend, no telemetry,
> and zero dependencies**. Logs are stored on-device as NDJSON and shared only when *you* tap
> share. It also does **not** redact anything — data is shown raw, which is exactly why it is
> a **non-production debug tool** (`#if !PROD`).

<!-- TODO: add a demo GIF here — shake → viewer → request detail (docs/demo.gif) -->

## Features

- [x] **One-line setup** — `startAutomaticCapture()` hooks every `URLSession` (Alamofire included) without touching your networking code, and without breaking SSL/pinning
- [x] **App + network logs in a single timeline** — categories, levels, call-site info, live stream
- [x] **Shake → viewer** — SwiftUI viewer with search, filters, session/history scopes, infinite-scroll pagination, pin & multi-select, Esc-to-close on simulator
- [x] **Request detail** — status banner, headers, pretty-printed & syntax-highlighted JSON, image previews, cURL
- [x] **Timing breakdown** — DNS / TCP / TLS / TTFB per request, protocol (h2/h3), connection reuse ("is the API slow, or the network?")
- [x] **Active requests bar** — in-flight calls shown live with elapsed time; spot a hung request instantly
- [x] **Response mocking** — return your own status/body/delay/transport-error without hitting the network; convert any captured response into a mock **on-device, no code**
- [x] **Decoding-error capture** — logs the exact failing field path (`user.accounts[0].iban`) next to the raw body
- [x] **Statistics** — error rate, avg/median/p95 durations, status & method distribution, slowest requests
- [x] **Export anywhere** — `.log`, raw NDJSON, **HAR 1.2** (Charles/Proxyman/DevTools), **Postman Collection v2.1**
- [x] **Bridges** — swift-log backend template, OSLog import, generic `ExternalToolBridge` for your own tools; `OlafUI.onLogoTap` hands off to another shake-activated tool via the nav-bar logo
- [x] **History across launches** — NDJSON persistence with rotation, retention, and file protection

## Quick Start

```swift
import Olaf

// At app startup — before your shared URLSession is created (wrap in #if !PROD):
Olaf.start(.default)                        // engine: disk + OSLog mirror
OlafNetwork.startAutomaticCapture()         // capture all network traffic
Task { @MainActor in OlafUI.install() }     // shake → viewer
```

That's it. Shake the device (or press <kbd>⌃⌘Z</kbd> in the simulator) and the viewer opens.
Log your own events too:

```swift
Olaf.info("Login succeeded", category: .auth, metadata: ["method": "biometric"])
Olaf.error(error, category: .payment)
```

## Installation

Xcode → **File → Add Package Dependencies…**

```
https://github.com/ersel95/olaf.git
```

or in `Package.swift`:

```swift
.package(url: "https://github.com/ersel95/olaf.git", from: "0.45.0")
```

Single product: `Olaf` — engine + network capture + viewer, one `import Olaf`.

> For a production-grade setup (an `OlafManager` facade, `#if !PROD` gating, category
> conventions), copy the drop-in template and follow **[INTEGRATION.md](INTEGRATION.md)**.
> AI agents can follow **[AGENTS.md](AGENTS.md)**.

## Requirements

| Platform | Swift | Xcode | Dependencies |
|----------|-------|-------|--------------|
| iOS 17+ (viewer) · macOS 14+ (engine, tests) | 5.9+ | 15+ | **None** |

## Network capture

```swift
OlafNetwork.startAutomaticCapture(OlafNetworkConfiguration(
    includedURLs: ["api-gateway"],                            // only your API (empty = all)
    excludedURLs: ["firebaseio", "crashlytics", "googleapis"] // hide SDK noise
))
```

Requests are re-sent through a single shared proxy session (connection pool & cookies preserved),
logged **raw** under the `.network` category, and validated with **system TLS** — pinning and the
OS trust chain are never bypassed.

### Response mocking

```swift
OlafNetwork.addMock(OlafMockResponse(urlContains: "/v1/accounts", json: #"{"accounts": []}"#))
OlafNetwork.addMock(.failure(urlContains: "/v1/rates", error: .timedOut, delaySeconds: 3))
```

Or entirely on-device: open any captured request → **Convert to Mock** → edit status/body/delay →
save. Manage active mocks via **⋯ → Mocks**.

<details>
<summary><b>Known limitations</b> (inherent to URLProtocol-based capture)</summary>

- WebSocket (`URLSessionWebSocketTask`) and background-session traffic are not captured — URLSession doesn't route them through `URLProtocol`.
- `uploadTask(fromFile:)` bodies are not captured; `httpBody`/`httpBodyStream` bodies are (the stream is read into RAM — prefer `capturesBodies: false` for very large uploads).
- Session-level settings of the host session (`waitsForConnectivity`, `allowsCellularAccess`, …) are not carried over; the request's own `timeoutInterval` is. Cookies are preserved via the shared `HTTPCookieStorage`.
- If the host enforces custom certificate pinning, the proxy may not pass that traffic — system validation applies, by design.

</details>

<details>
<summary><b>Architecture</b></summary>

```
Olaf (facade)
  └─ OlafRuntime            # lifecycle, kill switch, runtime level threshold
       └─ LogStore          # serial queue: ring buffer → disk → OSLog → live stream
            ├─ FilePersistence   # NDJSON, size-based rotation + retention + file protection
            ├─ LogFormatter      # plain text / NDJSON export
            └─ OSLogMirror       # os.Logger bridge (Console.app)

OlafNetwork (URLProtocol capture) ── OlafProxySession (single shared proxy, task→handler routing)
OlafUI (SwiftUI viewer, UIKit-gated) ── separate UIWindow, owns the shake gesture
```

- **Async & non-blocking** — `@autoclosure` messages below the threshold are never computed; all writes go through a serial queue.
- **Engine is UIKit-free** — builds and runs tests on macOS; the viewer is `#if canImport(UIKit)`-gated.

</details>

## Privacy & Security

- **Fully local.** No backend, no analytics, no network calls of its own. Data leaves the device only through the share sheet, by explicit user action.
- **No redaction, by design.** Everything is stored raw (including `Authorization`/`Cookie`); that's what makes it useful for debugging — and why you must gate it out of production builds.
- Ships with a [`PrivacyInfo.xcprivacy`](Sources/Olaf/PrivacyInfo.xcprivacy) manifest (no tracking, no data collection).

## Development

```bash
swift build && swift test                                          # macOS
xcodebuild -scheme Olaf -destination 'generic/platform=iOS' build  # iOS
```

91 tests, zero warnings. See the [CHANGELOG](CHANGELOG.md) for release history.

## License

MIT — see [LICENSE](LICENSE).

<p align="center">
  <img src="docs/olaf-logo.png" alt="Olaf" width="140">
</p>

# Olaf

[![CI](https://github.com/ersel95/olaf/actions/workflows/ci.yml/badge.svg)](https://github.com/ersel95/olaf/actions/workflows/ci.yml)

A generic, portable Swift logging + in-app log viewer library that lets you **view and share app logs** on-device. See the [CHANGELOG](CHANGELOG.md) for changes.

> **Purpose:** View and share the logs of users you've shipped a feature to on TestFlight, right on their device. Shake the device to open the logs as plain text.
>
> **Fully local:** There is no backend. Logs are stored on-device as NDJSON (history across sessions), and shared from the viewer as readable plain-text `.log`. No data is ever sent over the network.

## Status

| Phase | Scope | Status |
|---|---|---|
| **0 — Skeleton** | SPM, models | done |
| **1 — Core engine** | Ring buffer, NDJSON disk persistence + cross-session history, OSLog bridge, facade | done |
| **2 — Viewer (OlafUI)** | Shake → SwiftUI plain-text viewer, **Session/History** scope (paginated history — infinite scroll), filter/search/share, live stream, **dismiss with Esc** on simulator | done |
| **3 — Tool bridges** | Generic `ExternalToolBridge` + `presentExternal`; host can add its own external diagnostics tool to the viewer as a button, shake-ownership handoff (app side: `INTEGRATION.md` / `AGENTS.md`) | done |
| **N — Network capture (OlafNetwork)** | Optional URLProtocol; requests/responses in `.network` category, raw → app+network in a single list | done |
| **5 — UX & sharing** | Detail view (status banner, pretty-printed JSON body), sharing (Simple/Full log + cURL), copy toast, pre-start log buffering, per-session history | done |
| **4 — Bridges** | OSLogStore importer (`Olaf.importOSLogEntries` + viewer menu), swift-log backend (`Integration/OlafLogHandler.swift` template) | done |

## Installation (SPM)

```swift
.package(url: "https://github.com/ersel95/olaf.git", from: "0.44.0")
```
Single product: `Olaf` — engine (`Olaf` facade) + network capture (`OlafNetwork`) + viewer (`OlafUI`) all included.

> Instead of calling `Olaf.x(...)` directly in the app, it's recommended to log through the single
> integration point, `OlafManager` — see [`INTEGRATION.md`](INTEGRATION.md).

## Usage

```swift
import Olaf

// At app startup (once):
Olaf.start(.default)   // writes to disk, mirrors to OSLog

// Logging:
Olaf.info("Login succeeded", category: .auth, metadata: ["method": "biometric"])
Olaf.warning("Token needs refresh", category: .session)
Olaf.error("Transfer rejected", category: .payment, metadata: ["code": code])

// Reading / management (used by the viewer):
let entries = Olaf.snapshot()              // this session (in memory)
let history = Olaf.loadPersistedEntries()  // including previous sessions (from disk)
for await entry in Olaf.stream() { … }     // live stream
let url = Olaf.exportFileURL()             // shareable, readable .log
Olaf.clear()

// Kill switch:
Olaf.isEnabled = false
```

### In-app viewer (OlafUI)

Shake → Olaf viewer. Set up by the host at init:

```swift
// In the host integration file (Integration/OlafIntegration.swift):
OlafManager.shared.initialize()

// Package API:
OlafUI.install()                             // shake → viewer
OlafUI.present(); OlafUI.dismiss()
OlafUI.presentExternal { SomeView() }        // for embeddable SwiftUI tools
```

Olaf owns the shake gesture. To add your own external diagnostics tool to the viewer, use the
generic `ExternalToolBridge` + `OlafUI.register(_:)`; the button appears in the viewer's **bottom bar**:

```swift
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, or OlafUI.presentExternal { ... } */ }
}
OlafUI.register(SomeToolBridge())
```

### Listing network logs in Olaf (OlafNetwork)

**One line, no changes to your networking code** (URLSessionConfiguration swizzle + global; doesn't break SSL):

```swift
OlafNetwork.startAutomaticCapture()   // body+header capture on by default

// Filter which base URLs get captured, at init:
OlafNetwork.startAutomaticCapture(OlafNetworkConfiguration(
    capturesBodies: false,
    includedURLs: ["api-gateway"],                                   // only your own API (empty = all)
    excludedURLs: ["firebaseio", "crashlytics", "googleapis"]        // hide SDK noise
))
```
Requests/responses land in the Olaf list in the `.network` category, **raw**
(app + network in one place). Body + header capture is **on by default**; all data (including
`Authorization`/`Cookie`) is stored unmasked. **Base URL filtering** via `includedURLs`/`excludedURLs`,
with `excludedURLs` taking priority; requests outside the filter are never captured.

- **JSON bodies** are shown automatically with **pretty-printing + syntax highlighting** (detail → "View body"); `image/*` responses (up to 256 KB) are previewed in the detail view.
- **Share formats**: .log (plain text) · NDJSON (raw) · **HAR 1.2** (Charles/Proxyman/DevTools) · **Postman Collection v2.1**; Simple/Full log + cURL for a single entry.
- **Statistics** (⋯ menu): error rate, average/median/p95 duration, method/status distribution, slowest requests, hosts.
- **Decode error capture**: `OlafDecoding.decode(_:from:url:)` logs the full path of the failing field (`user.accounts[0].iban`) together with the raw body.
- **Response mocking**: `OlafNetwork.addMock(...)` — matching requests get your response without ever hitting the network (for simulating edge cases/5xx/slow network/timeouts); entries are marked `[mock]`. **On-device too**: detail → "Convert to mock" lets you edit a captured response and turn it into a mock; manage via ⋯ → Mocks.
- **Pin + multi-select**: pin entries (shown in a separate section at the top) and bulk-share via multi-select; content-type filter (JSON/XML/HTML/Image/Text).
- **Active requests**: in-flight requests (not yet responded) appear live at the top of the viewer with their elapsed time — catch a hung call instantly.
- **Timing breakdown**: for each request, DNS / TCP / TLS / TTFB durations, protocol (h2/h3), and whether the connection was reused, shown in the "Timing" section of the detail screen ("is it the API that's slow, or the network?").
- Manual injection into a specific config is also available via `install(into:)` (advanced).
- **For non-prod debugging only** (body/header logging) — do not run in PROD.

#### Known limitations (inherent to URLProtocol-based capture)
- **WebSocket** (`URLSessionWebSocketTask`) and **background session** traffic are not captured (URLSession doesn't route this traffic through URLProtocol).
- `uploadTask(fromFile:)` / upload stream bodies are not captured; `httpBody`/`httpBodyStream` bodies are captured (the stream is fully read into RAM — for very large uploads, `capturesBodies: false` is recommended).
- The host session's **session-level settings** (`waitsForConnectivity`, `allowsCellularAccess`, etc.) are not carried over to the proxy; the request's own `timeoutInterval` is preserved. Cookies are preserved via the shared `HTTPCookieStorage`.
- If the host applies **custom certificate pinning**, the proxy may not be able to pass that traffic through (the proxy doesn't share the host's trust delegate; system validation applies — this is safe and intentional behavior).

- **Step-by-step integration:** [`INTEGRATION.md`](INTEGRATION.md)
- **Machine-followable instructions for AI agents:** [`AGENTS.md`](AGENTS.md)
- **Single-file drop-in template:** [`Integration/OlafIntegration.swift`](Integration/OlafIntegration.swift)

## Architecture (Core)

```
Olaf (facade)
  └─ OlafRuntime          # lifecycle, kill switch, level threshold (lock-protected)
       └─ LogStore          # serial queue: ring buffer → disk → OSLog → live stream (raw, unmasked)
            ├─ FilePersistence        # size-based rotation + retention + data protection
            ├─ LogFormatter           # PlainText / JSON (NDJSON)
            └─ OSLogMirror            # os.Logger bridge (Console.app)
```

- **No masking/filtering** — message, metadata, and network body/header data are stored and displayed **raw**, exactly as they came from the call site. Preventing sensitive data leaks is the host's responsibility: only run capture in non-prod debug builds (`#if !PROD`).
- **No UIKit/SwiftUI dependency** → compiles and is testable on every platform.
- **Async/non-blocking** — with `@autoclosure`, the message isn't computed if it's below the level threshold; writes happen on a serial queue.

## Development

```bash
swift build
swift test
```

## License

MIT — see [LICENSE](LICENSE).

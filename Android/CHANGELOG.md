# Changelog — Olaf Android

The format is inspired by [Keep a Changelog](https://keepachangelog.com/en/); versioning follows
SemVer (0.x — API not yet stable). Android releases are tagged `android-x.y.z` so they stay
independent of the iOS package's own version line (see the [root CHANGELOG](../CHANGELOG.md)).

## [0.4.0] — 2026-07-23
### Added
- **HAR 1.2 and Postman Collection v2.1 export** of the visible network entries, alongside the
  existing `.log` and NDJSON shares. HAR opens directly in Charles/Proxyman/DevTools; the Postman
  collection deduplicates repeated `method + URL` pairs so it stays re-runnable.
- **Statistics**: request count, failure rate, bytes sent/received, average/median/p95 duration,
  status-class and method distribution, busiest hosts and slowest requests — all computed over the
  entries currently on screen.
- **Mock list**: view and remove registered mocks from inside the viewer.
- **Active requests bar**: in-flight calls with their elapsed time, so a hung request is obvious;
  anything over five seconds is highlighted.
- **Decoding-error capture** (`Olaf.logDecodingError`): lifts the failing field path out of Gson
  and Moshi messages (`$.user.accounts[0].iban`) and stores it with the raw body. Decode entries
  fold into the network row they belong to (same host+path, within 30s) and surface as a
  "Decoding errors" section in the detail view — while still matching the `decoding` chip, the
  ERROR level and search, so folding never hides a failure.
- **Detail additions**: cURL rendering with copy-to-clipboard, and an inline image preview for
  captured image responses.
- 16 further unit tests (91 total) over the exporters, statistics, cURL escaping, decode-path
  extraction and decode attachment.

## [0.3.0] — 2026-07-23
### Added
- **In-app viewer** (Jetpack Compose): shake the device — or call `OlafUI.present()` — and the
  viewer opens in its own activity, so the host's back stack and navigation graph stay untouched
  (the counterpart of iOS presenting it in a separate window).
- **List**: network rows with a status pill, method badge, path, host, time, duration and size;
  plain log rows with a level dot, category chip and level name. Search across message, category
  and metadata (debounced), category chips, a filter sheet for level/category/content type, pin &
  pinned section, pause/resume of the live stream.
- **Session / History scopes**: History groups entries by previous session and pages through disk
  history as you scroll, with a manual "Load older entries" fallback.
- **Detail screen**: status/method/URL header, call-site and thread, summary (duration, sizes),
  the full timing breakdown, request/response headers and pre-formatted bodies, all selectable,
  plus copy-to-clipboard.
- **Sharing** of the visible (filtered) entries as `.log` or raw NDJSON, through a `FileProvider`
  declared by the library itself — the host configures nothing.
- **`ExternalToolBridge`** and **`OlafUI.onLogoTap`**, so Olaf can hand off to another
  shake-activated diagnostics tool.
- 14 further unit tests (75 total) covering the viewer's filtering, session grouping, default chip
  selection and network metadata parsing.

### Changed
- Call-site capture now skips OkHttp/Okio frames, so a captured request is attributed to the code
  that issued it (`SampleActivity.kt:69`) rather than to `RealInterceptorChain.proceed`.

### Verified
- Ran on a Pixel 9a emulator: real requests captured (200/500), the network chip preselected,
  detail showing DNS/TCP/TLS/TTFB, `h2` and connection reuse.

## [0.2.0] — 2026-07-23
### Added
- **Network capture** (`OlafNetwork.interceptor()`): an OkHttp application interceptor that logs
  method, URL, status, duration, byte counts, raw bodies and raw headers under the `network`
  category. Bodies are peeked rather than consumed, so the caller still reads the response
  normally; JSON is pretty-printed at capture time. Allow/deny URL filters, body/header toggles,
  a body length cap, and an image preview attached as base64 under the configured size limit.
- **Timing breakdown** (`OlafNetwork.eventListenerFactory()`): DNS / TCP connect / TLS / TTFB,
  negotiated protocol and connection reuse — the counterpart of iOS's `URLSessionTaskMetrics`.
- **Response mocking** (`OlafMockResponse`): match by URL fragment and method, return a canned
  status/body/headers, simulate a slow response (`delayMillis`) or a transport failure
  (`TransportError`). Mocks short-circuit the chain, so no request is made, and they take priority
  over the capture filters. First matching mock wins.
- **Active requests registry** feeding the viewer's in-flight bar.
- **One-line install**: `OkHttpClient.Builder().installOlaf()`.
- 29 further unit tests (61 total) covering capture, filters, truncation, image previews, error
  and cancellation paths, the iOS-compatible metadata contract, and mock delivery/priority.

### Notes
- iOS captures every session automatically by swizzling `URLSessionConfiguration`; OkHttp has no
  equivalent global hook, so the interceptor must be added to the client — the same single line
  Chucker requires. In exchange the host's TLS, pinning and timeout settings apply untouched,
  which is why iOS's `allowsArbitraryServerTrustForCapture` has no counterpart here.
- OkHttp allows only one `EventListener.Factory` per client. If the app already installs its own,
  use `installOlaf(withTiming = false)`: everything except the timing section keeps working.

## [0.1.0] — 2026-07-23
### Added
- **Core engine**, ported from the iOS package: the `Olaf` facade (`start`, `trace`…`critical`,
  `error(Throwable)`, `trackScreen`, `snapshot`, `stream`, `clear`, export), a fixed-capacity ring
  buffer, NDJSON disk persistence with size-based rotation and file-count retention, cross-session
  history with file-bounded pagination, pre-start buffering, and a Logcat mirror (the counterpart
  of the iOS OSLog bridge).
- **Same on-disk schema as iOS** — field names, the level ordinal and the raw category string all
  match, so the same `jq`/tooling works against either platform. Android writes millisecond
  timestamps and reads iOS's second-precision ones.
- **Lambda log overloads** (`Olaf.debug { "…" }`) as the counterpart of Swift's `@autoclosure`:
  a message below the collection threshold is never built. Call-site info (file/line/function) is
  recovered from the stack, and only for entries that are actually recorded.
- 32 unit tests covering the ring buffer, persistence, rotation/retention, history pagination,
  the NDJSON codec (including reading iOS-written lines and skipping corrupt ones), formatters and
  pre-start buffering.
- Gradle build skeleton: `:olaf`, `:olaf-no-op` and `:sample` modules, a version catalog aligned
  with the host app (AGP 8.12.2, Kotlin 2.1.20, Compose BOM 2025.09, OkHttp 5.1.0),
  `maven-publish` wiring for `com.github.ersel95.olaf:olaf` / `:olaf-no-op`, and an `android` CI
  job next to the iOS one.

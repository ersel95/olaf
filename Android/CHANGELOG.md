# Changelog — Olaf Android

The format is inspired by [Keep a Changelog](https://keepachangelog.com/en/); versioning follows
SemVer (0.x — API not yet stable). Android releases are tagged `android-x.y.z` so they stay
independent of the iOS package's own version line (see the [root CHANGELOG](../CHANGELOG.md)).

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

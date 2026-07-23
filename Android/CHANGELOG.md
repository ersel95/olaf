# Changelog — Olaf Android

The format is inspired by [Keep a Changelog](https://keepachangelog.com/en/); versioning follows
SemVer (0.x — API not yet stable). Android releases are tagged `android-x.y.z` so they stay
independent of the iOS package's own version line (see the [root CHANGELOG](../CHANGELOG.md)).

## [0.10.0] — 2026-07-23
### Added
Closing the gaps found by comparing against Chucker:

- **Capture notification**: captured requests appear in the notification shade with a running
  count, and tapping opens the viewer. Shaking is awkward on an emulator and impossible with the
  device on a desk — this is the always-available way in. Low importance, so it never interrupts;
  silently inert without the notification permission, which the host requests (or doesn't).
- **Launcher shortcut**: long-pressing the app icon offers "Olaf", with no host code at all.
- **Its own task**: the viewer no longer shares the host's task, so on tablets and foldables it
  can sit side by side with the app being debugged instead of replacing it.
- **`BodyDecoder`**: pluggable decoders for bodies Olaf can't read as text — Protobuf, MessagePack,
  anything. Tried in order, first non-null wins, and a decoder that throws is skipped rather than
  breaking the request. Gzip needs none (OkHttp handles it); for Brotli, install OkHttp's
  `BrotliInterceptor` *after* Olaf's so Olaf observes the decoded body — documented on the
  interface.
- **Age-based retention** (`retentionMillis`, default one day) alongside the file-count cap.
  Both are needed: the count alone lets a quiet week keep month-old logs, the age alone lets a busy
  hour fill the disk. Whichever bites first wins.
- 7 further unit tests (108 total) over retention pruning, decoder fallthrough and decoder failure.

### Notes
- Chucker's `redactHeaders` has no counterpart, deliberately: storing everything raw is the point
  of the tool, and keeping production safe is what the no-op artifact is for.

## [0.9.0] — 2026-07-23
### Changed
- **Distribution is now tag-driven.** Artifacts are built from the git tag by JitPack, so there is
  no publishing infrastructure, no account and no secret to maintain, and consumers add one
  repository line:

  ```kotlin
  maven { url = uri("https://jitpack.io") }
  debugImplementation("com.github.ersel95.olaf:olaf:android-0.9.0")
  releaseImplementation("com.github.ersel95.olaf:olaf-no-op:android-0.9.0")
  ```

  The artifact version *is* the tag, so it is always obvious which commit a build came from. The
  build takes its version from `-Pversion` when CI or JitPack passes the tag, and from a local
  constant otherwise — cutting a release no longer means editing the build file.
- **`scripts/release.sh <ios|android> <x.y.z>`** runs every gate before the tag exists: clean tree,
  free tag, a matching CHANGELOG section, version consistency, then the full test and build
  verification — including the sample compiled against both artifacts. `--dry-run` shows the
  release notes without tagging.
- Release notes are generated from the CHANGELOG, and a missing section fails the release instead
  of publishing empty notes.

## [0.8.0] — 2026-07-23
### Changed
- **Native Material 3 pass over the viewer.** The port matched iOS's information architecture but
  not yet Android's visual language; this closes that gap:
  - **Dynamic colour** on Android 12+, so the viewer takes the device's theme instead of imposing
    a fixed palette. Semantic colours (status pills, level dots) stay fixed — a 500 has to read as
    a failure whatever the wallpaper is.
  - **Edge-to-edge**, the platform default from Android 15 on; the scaffolds inset their own
    content, which also removes the dead band under the status bar.
  - **Correct icons**: a filter funnel and a pin, drawn from Material's own geometry, replacing the
    list/star stand-ins that read wrong. Still `material-icons-core` only.
  - **Search field** with a leading search icon, a clear button that appears only when there is
    something to clear, and a pill shape.
  - **Empty state** that names what is missing and offers the way out, instead of a blank screen.
  - **Haptic feedback** on pin, which otherwise has no confirmation.
  - An entry with no metadata now says so rather than rendering an empty detail screen.

## [0.7.0] — 2026-07-23
### Added
- **Timber bridge template** (`Integration/OlafTimberTree.kt`): plant it next to `DebugTree` and
  every existing `Timber` call — including those from libraries — lands in the viewer, with the
  Timber tag as the category. The counterpart of the iOS package's swift-log handler, and the
  reason no call site has to change. Olaf itself keeps no Timber dependency; the tree is a
  drop-in file.
- **`OlafDecoding.decode`**: wraps a parse, logs the failure with its field path, and rethrows it
  untouched. Parser-agnostic — it takes a lambda, so Gson, Moshi and kotlinx.serialization all work
  without Olaf depending on any of them.
- **`OlafViewer` composable**: the viewer embeddable in an existing screen (a developer-settings
  page, say) instead of being presented as its own activity.
- **DECODE badge** on the list row of a request whose response failed to decode — without it, a
  folded decode error was only discoverable by opening the detail.
- **Collapsible header rows**: a long value (`set-cookie`, bearer token) shows a one-line preview
  and expands on tap, so fifty headers stay navigable.
- **Copy confirmation** via snackbar, since the platform only shows its own on Android 13+.

## [0.6.0] — 2026-07-23
### Added
- **JSON syntax highlighting** in bodies and in the cURL block, regex-based rather than
  parser-based so truncated payloads still get coloured.
- **Full-screen text viewer** for bodies and cURL: search, line-wrap toggle, selection and copy.
  Searching **keeps JSON blocks whole** — a hit on a key whose value is an object or array pulls in
  the entire block down to its matching close, since a lone `"accounts": [` line tells the reader
  nothing; disjoint results are separated with `⋯` and keep their highlighting.
- **Convert to mock**: turn any captured response into an editable mock on the device — URL
  fragment, method scoping, status, body, delay, or a transport failure instead. The captured
  response headers carry over.
- **Multi-select and share**: pick entries from the session list and export just those.
- **Logcat import** (`Olaf.importLogcatEntries`): pulls this process's Logcat output — including
  messages from SDKs that know nothing about Olaf — into the same list and the same export. The
  counterpart of iOS's OSLog import; Olaf's own mirrored entries are skipped so nothing duplicates.
- **Collapsible detail sections**, so a response with fifty headers stays navigable. Summary and
  cURL start collapsed.
- The Olaf logo now appears in the viewer's app bar (and is the hand-off button when
  `OlafUI.onLogoTap` is set), replacing the plain text title.
- 10 further unit tests (101 total) over JSON-block search, bracket depth inside string literals,
  and Logcat line parsing including the year-boundary case.

## [0.5.0] — 2026-07-23
### Added
- **`olaf-no-op` artifact**, the release counterpart wired up exactly like Chucker's
  (`debugImplementation` / `releaseImplementation`). It mirrors the public API with empty bodies,
  so host code compiles unchanged while no capture, no viewer and no stored logs reach the
  production APK; `installOlaf` leaves the client entirely untouched there.
- **API-drift protection**: the sample compiles against `:olaf` in debug and `:olaf-no-op` in
  release, so any signature that diverges breaks `:sample:assembleRelease` — in CI, not in
  someone's production build.
- **Documentation**: `Android/README.md`, `INTEGRATION.md` (production-grade host setup),
  `AGENTS.md` (mechanical steps for AI agents), `CLAUDE.md` (rules for this subtree), and the
  drop-in `Integration/OlafManager.kt` template. The root README and CLAUDE.md now describe the
  two-platform layout.

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

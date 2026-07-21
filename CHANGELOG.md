# Changelog

The format is inspired by [Keep a Changelog](https://keepachangelog.com/en/); versioning follows SemVer
(0.x — API not yet stable). For older versions, see the git tag history.

## [0.45.0] — 2026-07-21
### Changed
- **Collapsible header rows**: on the Request/Response Headers screens each row is now a
  disclosure — collapsed by default with a single-line value preview, expanded to the full
  selectable value.
- **Collapsible detail sections**: the titled sections of the network detail view (Summary,
  Error, Request, Response, Timing, Metrics) can be collapsed/expanded by tapping the section
  header. Summary starts collapsed; all other sections start expanded.

## [0.44.0] — 2026-07-20
### Changed
- **Full English localization**: all Turkish content — code comments, viewer UI strings, log
  message markers, README/CHANGELOG/INTEGRATION/AGENTS docs, DocC catalog, integration
  templates — translated to English for global use. Notable user-visible string changes:
  cancelled marker is now "→ cancelled", statistics status classes are "Error"/"Cancelled",
  decoding error messages are in English. `docs/bug-reporter-ozet.md` renamed to
  `docs/bug-reporter-summary.md`. No API, metadata key, or behavior changes.

## [0.43.0] — 2026-07-20
### Added
- **Convert to mock from the viewer**: "Convert to mock" in a network entry's detail view — the
  captured response opens in an editable editor (URL pattern, method restriction, status/body,
  delay, transport error selection), and once saved, the mock becomes active on-device without
  writing any code.
- **Mock list** (⋯ → Mocks): view active mocks, swipe to delete individually,
  "Remove all". `OlafMockResponse` is now `Identifiable`; `OlafNetwork.removeMock(id:)`.

## [0.42.0] — 2026-07-20
### Added
- **Response mocking**: `OlafNetwork.addMock(OlafMockResponse(...))` — matching requests get the
  defined response without hitting the network (status/header/body, `delaySeconds` for a slow
  network, `.failure(...)` for simulating transport errors). The first mock added wins; capture URL
  filters don't affect mocks. Entries are logged with a `[mock]` marker, and the detail view shows
  "Source: Mock".

## [0.41.0] — 2026-07-20
### Added
- **Pinning**: long-press an entry and "Pin" — pinned entries appear above the session list, in a
  separate section independent of filters (session-scoped; not persistent).
- **Multi-select sharing** (⋯ → Select): mark multiple entries in the session list and share them
  as a single `.log` file.

## [0.40.0] — 2026-07-20
### Added
- **Content-type filter** (filter screen → "Content type"): network responses can be filtered by
  JSON/XML/HTML/Image/Text/Other classes (only those types are listed when selected).
- **Image preview**: `image/*` response bodies are captured and previewed in the detail screen if
  under the `maxImageBodyBytes` limit (default 256 KB)
  (`OlafNetworkConfiguration.maxImageBodyBytes`, `0` = disabled).

## [0.39.0] — 2026-07-20
### Added
- **Decode error capture**: `OlafDecoding.decode(_:from:url:)` (a JSONDecoder wrapper that rethrows
  the original error as-is) and `Olaf.logDecodingError(_:url:data:typeName:)` — extracts the full
  path of the failing field (`user.accounts[0].iban`), logs it to the `.decoding` category together
  with the raw body; a "Decode Error" section appears in the detail screen.

## [0.38.0] — 2026-07-20
### Added
- **Postman Collection export** (⋯ → Share → "Postman Collection"): visible network
  requests are exported as a Collection v2.1 (deduplicated by method+URL); can be imported into
  Postman and re-run.

## [0.37.0] — 2026-07-20
### Added
- **Statistics screen** (⋯ → Statistics): for the visible network entries — error rate,
  average/median/p95 duration, total sizes, status class and method distribution (bar chart),
  the 5 slowest requests, and the hosts receiving the most requests.

## [0.36.0] — 2026-07-20
### Added
- **HAR export**: visible network entries can be shared as a HAR 1.2 document
  (opens directly in Charles/Proxyman/Chrome DevTools) — ⋯ → Share → "HAR (network)".
  Timing phases (dns/connect/ssl/wait/receive) are mapped to HAR timings.

## [0.35.0] — 2026-07-20
### Added
- **History pagination**: `Olaf.loadPersistedPage(before:minimumEntries:)` — history is no longer
  loaded all at once, but page by page from newest to oldest with a file-bounded cursor. Infinite
  scroll + "Load older" row in the viewer; an info note that search/filters apply to loaded entries.
  No duplicate entries occur across pages even if rotation happens in between.
- **Dismiss with Esc**: pressing Esc on a hardware keyboard (Mac keyboard in the simulator) closes
  the viewer; when an external tool opened via `presentExternal` is showing, Esc first dismisses
  the tool and returns to the viewer.

## [0.34.0] — 2026-07-20
### Added
- `PrivacyInfo.xcprivacy` — SDK privacy manifest (no data collection, no tracking; only a
  file-timestamp read declaration `C617.1` for rotation).
- DocC catalog (`Olaf.docc`) — API documentation landing page + topic groups.
- `CHANGELOG.md` (this file) and a CI badge on the README.

## [0.33.0] — 2026-07-20
### Added
- **OSLogStore importer**: `Olaf.importOSLogEntries(since:category:excludingSubsystems:)` —
  imports this process's OSLog entries (including `os_log` output from other SDKs) into Olaf;
  "Import OSLog (1 hour)" in the viewer menu. Added `LogCategory.oslog`.
- **swift-log backend template**: `Integration/OlafLogHandler.swift` —
  with `LoggingSystem.bootstrap`, all `Logging.Logger` calls flow into Olaf
  (not a package dependency, per the zero-dependency rule — a template copied into the host).

## [0.32.0] — 2026-07-20
### Added
- `Olaf.minimumLevel` — the collection threshold can be changed at runtime; a "Collection
  threshold" setting in the filter screen.
- NDJSON export: `Olaf.exportNDJSONFileURL(entries:)` + "Share (NDJSON)" in the viewer.
### Changed
- Derived viewer values (`filteredEntries`/`sessionGroups`/`availableCategories`) are now
  memoized: computed once when inputs change rather than on every render (prevents stutter with
  a large History).

## [0.31.0] — 2026-07-20
### Added
- **Active requests bar**: in-flight requests appear live at the top of the viewer with their
  elapsed time (`OlafNetwork.pendingRequests`); hung requests are noticed instantly.
- **Timing breakdown**: from `URLSessionTaskMetrics` — DNS / TCP / TLS / TTFB, protocol
  (h2/h3), and connection reuse — a "Timing" section in the detail screen.
- README/INTEGRATION: documented the known limitations of URLProtocol-based capture.

## [0.30.0] — 2026-07-20
### Changed
- **Shared proxy session** (`OlafProxySession`): a single session instead of an ephemeral
  per-request session — connection pooling/TLS reuse; the shared `HTTPCookieStorage` is
  preserved (cookie-based sessions aren't broken by capture).
- Canceled requests (`NSURLErrorCancelled`) are logged as `.info` ("→ canceled"), not `.error`.
- Swift 6 concurrency warnings eliminated (delegate conformance moved to the manager class).
### Added
- GitHub Actions CI (macOS test + iOS build) and network layer tests.

## [0.29.0] — 2026-07-20
### Removed (BREAKING)
- The bug-reporter/upload mechanism (`OlafUpload` target, BugReport UI flow,
  `ScreenshotDetector`, `LogCategory.screenshot`) — to be developed in a separate project;
  see summary: `docs/bug-reporter-summary.md`.
### Changed (BREAKING)
- Single SPM product/target: `OlafCore` + `OlafUI` + `OlafNetwork` → `Olaf`
  (the host adds a single product, a single `import Olaf`).

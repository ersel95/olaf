# Bug-Reporter Mechanism — Summary of Removed Code

> This document is a complete summary of the "report errors to the backend" mechanism
> (OlafUpload + the OlafUI bug-report flow) that was **removed** from the Olaf package. Olaf is
> now solely a network logger. This mechanism will be redeveloped **in a separate project**; this
> document is a reference for that development. The final state of the removed code lives in git
> history: check the commit **before** this change (`git log docs/bug-reporter-summary.md` to find
> the parent of the commit that added this document).

## 1. Overall flow (end to end)

```
User takes a screenshot
  → ScreenshotDetector (userDidTakeScreenshotNotification) renders the key window itself
  → BugReportBanner shows a "Want to share it?" bubble from the bottom, in a separate UIWindow
  → [Yes] → BugReportSheet (form: "What happened?" / "What should have happened?" / name on first use)
  → BugReportComposer: compresses the screenshot to JPEG + collects device identity + telemetry
  → OlafBugReportService.sendReport: builds the payload (including a log snapshot)
  → OlafUploadQueue.submit → OlafUploader (multipart POST /reports)
  → Success: "Sent" toast · Transient error: queued to disk, retried with backoff
```

Two **gates** (defense layers):
1. **Local opt-in** (build-time): no code runs (remote config, detector, upload) unless
   `OlafUpload.configure(enabled: true, apiKey:, baseURL:)` is called. Default is **off**.
2. **Server-side kill switch** (runtime): `GET /config` → `captureEnabled`. If `false`, the banner
   is never shown. **Fail-closed**: if the config can't be fetched, `.disabled` is assumed.

## 2. Module map (removed files)

### `Sources/OlafUpload/` (entire target)

| File | Responsibility |
|---|---|
| `OlafUpload.swift` | Facade. `configure(enabled:apiKey:baseURL:environment:)` is the single, idempotent entry point. Holds the service + detector-installer hook via a `StateBox` (NSLock). The UI layer connects without a UIKit dependency via `setDetectorInstaller` (order-independent: configure can be called before or after). Recursion prevention: adds the upload/config endpoints to `OlafNetwork.excludedURLs`. |
| `OlafUploadConfiguration.swift` | Config struct: `apiKey` (a single secret, sent via the `x-olaf-api-key` header; the backend identifies the app from it), `baseURL`, `environment`, `reportsPath` (`/api/v1/olaf/reports`), `configPath` (`/api/v1/olaf/config`), `requestTimeout` (30s), `maxRetryCount` (5), `baseRetryDelay` (5s), `screenshotJPEGQuality` (0.7), `maxScreenshotBytes` (4 MiB). `captureExclusionFragments`: the host + two paths (to be excluded from capture). No real URL/secret is embedded as a default. |
| `OlafBugReportService.swift` | The working engine. `bootstrap()`: fetches remote config + drains the queue. `isCaptureEnabled` (gate 2), `maxScreenshotBytes` = min(local, remote). `sendReport(whatHappened:whatExpected:testerName:screenshotJPEG:identity:telemetry:)`: builds the payload, adds `entries: Olaf.snapshot()` (ALL categories, raw LogEntry[]), and sends via the queue. Saves the tester's name to Keychain. |
| `OlafUploader.swift` | The HTTP client. **Its own ephemeral URLSession, with `protocolClasses = []`** → the capture protocol isn't injected, so there's no recursion. Result classification: 2xx = success · 4xx = permanent error (drop from queue; **except 408/429** → transient) · 5xx/network error = transient (queue + backoff). `makeMultipartBody`: the `report` part is sent as a **file part** with `filename="report.json"` (some multipart parsers don't bind a text field to the body), the `screenshot` part as `image/jpeg` binary. |
| `OlafUploadQueue.swift` | An offline queue (an `actor`). Under `Caches/Olaf/uploads/`, an envelope (`{id}.json`: boundary, attempt, createdAt, nextAttemptAt) + body (`{id}.body`) pair. Writing: `.atomic` + `.completeFileProtection` on iOS. Exponential backoff: `baseRetryDelay * 2^attempt`, up to `maxRetryCount` attempts. **48-hour TTL**: stale reports are deleted without being sent (so sensitive data doesn't sit on disk indefinitely). `drain()` is idempotent (an `isDraining` flag). Resumes from disk even if the process restarts. |
| `OlafRemoteConfig.swift` | The `GET /config` response: `captureEnabled` (default **false**), `maxScreenshotBytes` (default 4 MiB). `OlafRemoteConfigClient` also uses its own session (empty protocolClasses). Error → `.disabled`. |
| `OlafReportPayload.swift` | The data contract (see §3 below). |
| `OlafTelemetry.swift` | A point-in-time device-state collector + `OlafNetworkMonitor` (an NWPathMonitor cache — wifi/cellular/wired/none). `prepare()`: starts battery monitoring + the network monitor early, while the banner is being set up, so the first report is populated. Memory: mach `task_vm_info.phys_footprint`. IP/SSID/location are not collected. |
| `OlafDeviceIdentity.swift` | A persistent device identity: **a UUID in Keychain** (survives uninstall; first generated from `identifierForVendor`, or randomly if unavailable). Tester name: asked **once**, stored in Keychain (`kSecAttrAccessibleAfterFirstUnlock`); the old UserDefaults value is migrated once. Device metadata: `utsname.machine` model (`SIMULATOR_MODEL_IDENTIFIER` on simulator), OS version, locale, screen (nativeBounds). App metadata: bundleId, `CFBundleShortVersionString`, `CFBundleVersion`. A minimal, dependency-free `KeychainStore` wrapper. |

### `Sources/OlafUI/Presentation/` (bug-report UI files)

| File | Responsibility |
|---|---|
| `ScreenshotDetector.swift` | Observes `userDidTakeScreenshotNotification`. The system doesn't hand the screenshot to the app → the key window is rendered via `UIGraphicsImageRenderer` + `drawHierarchy(afterScreenUpdates: true)` (**this is the only way the secure-text-field mask is actually effective** — hidden fields don't leak into the image). Olaf's own windows (`windowLevel >= .alert`) are excluded. The result is published via the `.olafScreenshotCaptured` notification (with a UIImage object). Also logged to the timeline via `Olaf.log(.info, "Screenshot taken", category: .screenshot)`. |
| `BugReportBanner.swift` | The orchestrator. A separate `UIWindow` (`windowLevel = .alert + 1`) + the **PassthroughView** pattern: while the banner is visible, only the banner's area captures touches, and the rest passes through to the app underneath (the app stays interactive). Auto-dismisses after 6 seconds of no interaction. [Yes] → presents `BugReportSheet` as a `.formSheet`. `OlafTelemetry.prepare()` is called during `install()`. |
| `BugReportSheet.swift` | A SwiftUI form. Fields: a screenshot preview + an **informed-consent warning** ("the image contains ALL information on screen; don't send it if it has sensitive data"), name on first use, "What happened?", "What should have happened?". UX: `@FocusState` field order, a keyboard toolbar ("Next"/"Done"), scrolling the focused field above the keyboard (`ScrollViewReader`), `interactiveDismissDisabled` while submitting. Error → an inline banner + retry ("it will be queued if it fails"). |
| `BugReportComposer.swift` | The UI → service bridge. JPEG encoding: first reduce quality (0.7 → 0.2, in steps of 0.15), and if still too large, **shrink the dimensions by a factor of 0.7** (min 320pt) — until it's under `maxScreenshotBytes`. `OlafDeviceIdentity.current()` + `OlafTelemetry.capture()` are gathered on MainActor. |
| `BugReportToast.swift` | The "Sent" toast — a separate, temporary `UIWindow` (`alert + 2`), ignores touches, fades after 2 seconds. |
| the hook inside `OlafUI.swift` | `OlafUI.install()` → `OlafUpload.setDetectorInstaller { BugReportBanner.shared.install() }`. This does **not run** the setup, it only provides the hook; the banner is only installed once the host calls `configure(enabled: true)`. |

### Other removed items
- `Tests/OlafUploadTests/` — `ReportPayloadTests`, `RemoteConfigTests`, `OlafUploadConfigurationTests`, `MultipartBodyTests`, `OptInGateTests`.
- `LogCategory.screenshot` (OlafCore) — used only by this flow.
- The OlafUpload section inside the `Integration/OlafIntegration.swift` template (Info.plist/xcconfig keys: `OLAF_BUG_REPORTER_ENABLED`, `OLAF_API_KEY`, `OLAF_API_BASE_URL`, `OLAF_ENVIRONMENT`).
- `INTEGRATION.md` §6 (the bug-reporter setup/troubleshooting guide).

## 3. Data contract (backend API)

### `POST {baseURL}/api/v1/olaf/reports` — multipart/form-data
- Header: `x-olaf-api-key: <apiKey>` (auth + app identification; no appKey/slug is otherwise carried).
- Part `report` (application/json, `filename="report.json"`):

```jsonc
{
  "app":    { "bundleId": "…", "version": "1.2.3", "build": "456", "environment": "staging" },
  "device": { "id": "<keychain-uuid>", "name": "Tester Name|null", "model": "iPhone15,3",
              "osVersion": "17.4", "locale": "tr_TR", "screen": "1179x2556" },
  "report": { "whatHappened": "…", "whatExpected": "…",
              "capturedAt": "ISO-8601", "sessionId": "<Olaf.currentSessionID>" },
  "telemetry": {                       // optional; a field that couldn't be collected is null (jsonb server-side)
    "timezone": "Europe/Istanbul", "screenScale": 3.0, "screenPoints": "390x844",
    "networkType": "wifi|cellular|wired|none|unknown",
    "batteryLevel": 87, "batteryState": "charging|full|unplugged|unknown",
    "lowPowerMode": false, "thermalState": "nominal|fair|serious|critical",
    "orientation": "portrait|…", "freeDiskBytes": 0, "totalDiskBytes": 0,
    "totalMemoryBytes": 0, "appMemoryBytes": 0
  },
  "entries": [ /* raw LogEntry[] — ALL categories, no masking */ ]
}
```

- Part `screenshot` (image/jpeg, `filename="screenshot.jpg"`) — optional.
- Encoding: `JSONEncoder` + `.iso8601` date + `.withoutEscapingSlashes`.

### `GET {baseURL}/api/v1/olaf/config`
- Header: `x-olaf-api-key`. Response: `{ "captureEnabled": bool, "maxScreenshotBytes": int }`.
- Fields are optional on decode; if missing, `captureEnabled=false`, `maxScreenshotBytes=4 MiB`.

## 4. Design decisions to preserve when redeveloping this

1. **Opt-in + fail-closed double gate** — against being accidentally enabled in prod: local `enabled`
   (default false, from xcconfig) + server `captureEnabled` (defaults to off if config can't be fetched).
2. **Recursion prevention (two safeguards)** — the uploader uses its own session (`protocolClasses=[]`)
   AND the upload/config URLs are added to the network-capture exclude list.
3. **Offline resilience** — a persistent disk queue, exponential backoff, permanent/transient error
   distinction (drop 4xx but treat 408/429 as transient), 48-hour TTL, `.completeFileProtection`.
4. **Screenshot safety** — `drawHierarchy(afterScreenUpdates: true)` (secure field masking),
   excluding its own overlay windows from rendering, an informed-consent text in the sheet,
   progressive JPEG compression/downscaling up to the size limit.
5. **Identity** — the device UUID and tester name live in Keychain (survive reinstall); the name is asked once.
6. **UIKit-free core + hook pattern** — the upload layer doesn't depend on UI; the UI registers an
   installer closure that fires once configure succeeds (order-independent).
7. **Separate-window UI** — the banner/toast/sheet don't touch the app hierarchy; passthrough hit-testing
   keeps the app interactive.
8. **apiKey is the one secret** — never committed to the repo, provided by the host via xcconfig/Info.plist;
   baseURL is not a secret.
9. **Telemetry contains no PII** — no IP/SSID/location; only device-state fields.

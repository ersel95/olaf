# Olaf — Integration Guide

A guide for wiring Olaf into your app.

> **Design principle:** Olaf is not tied to any external tool. External diagnostics tools
> (e.g. another network logger) can be added on the host side via the generic `ExternalToolBridge`.
> Fast path: the single-file template [`Integration/OlafIntegration.swift`](Integration/OlafIntegration.swift)
> and the machine-followable [`AGENTS.md`](AGENTS.md).

> **Gating note:** A TestFlight build is usually in a UAT/Prod config; `#if DEBUG` is only defined in the Test config.
> Don't tie Olaf to `#if DEBUG` — use the `#if !PROD` compile-time boundary (recommended, keeps capture code
> out of the prod binary) or a runtime feature flag.

---

## 1. Add the package

Xcode → Add Packages → `https://github.com/ersel95/olaf` → to your main app target ("Choose Package Products"):
- `Olaf` — **single product**: engine + network capture + in-app viewer all included.

> **Feature matrix — which call turns on which feature:**
>
> | Feature | Enabled by |
> |---|---|
> | Log API (trace…critical) | `Olaf.start(...)` |
> | Shake → log viewer | `OlafUI.install()` |
> | Network capture | `OlafNetwork.startAutomaticCapture()` |
> | Navigation breadcrumb | `Olaf.trackScreen(...)` (§6) |

## 2. Copy the integration file

Copy [`Integration/OlafIntegration.swift`](Integration/OlafIntegration.swift) into the host app (e.g. `Core/Utils/`).
It contains `OlafManager` (startup + logging), ready to go. Adapt the `// ADAPT:` lines.

```swift
@_exported import Olaf

public final class OlafManager {
    public static let shared = OlafManager()
    private init() {}

    public func initialize() {
        #if !PROD
        Olaf.start(.default)
        OlafNetwork.startAutomaticCapture()
        Task { @MainActor in
            OlafUI.install()
        }
        #endif
    }
}
```

## 3. Wire up startup

At your app's entry point — **BEFORE the shared URLSession is set up** (at the start of SwiftUI's
`App.init` or `AppDelegate.didFinishLaunching`, before any session preloading):
```swift
OlafManager.shared.initialize()
```
The shake gesture belongs to Olaf; shaking the device opens the viewer.

## 4. Listing network logs in Olaf — `OlafNetwork`

Logs requests/responses **raw** (unmasked) in the `.network` category.

### RECOMMENDED: one-line automatic capture (no changes to your networking code)
`startAutomaticCapture()` injects the protocol into all sessions (including Alamofire) by
swizzling `URLSessionConfiguration`. The proxy session **leaves TLS validation to the system**
(`.performDefaultHandling`) → the capture layer does **not override/bypass** the host's cert
pinning or the OS trust chain; invalid certificates are still rejected. (Note: as a result, only
certificates accepted by the device's system trust chain are captured; if the host applies its
own custom pinning, that traffic may fail through the proxy — this is expected and safe behavior.)
Already wired up in `initialize`:
```swift
OlafNetwork.startAutomaticCapture()                                // body+header capture on by default
OlafNetwork.startAutomaticCapture(OlafNetworkConfiguration(
    capturesBodies: false,
    includedURLs: ["api-gateway"],                                   // empty = all
    excludedURLs: ["firebaseio", "crashlytics", "googleapis"]        // hide SDK noise (takes priority)
))
```

### If you have your own custom session: deterministic injection
If the host sets up its own `URLSessionConfiguration`, instead of automatic swizzling, add one line when setting up the session:
```swift
// The configureNetworkCapture(_:) helper inside OlafManager:
OlafManager.shared.configureNetworkCapture(configuration)
// (internally: OlafNetwork.install(into: configuration))
```
If you use this, `startAutomaticCapture` is not needed. To chain another capture tool's URLProtocol
onto the same traffic, use `OlafNetwork.install(into:chainingTo:)`.

> **Security:** Body/header capture is on by default → all traffic is logged **raw** (no
> masking/filtering; everything, including token/PAN/IBAN/Authorization, is stored as-is). The
> capture layer NEVER relaxes TLS validation (cert pinning is not bypassed). Preventing sensitive
> data leaks is the host's responsibility → capture is **for non-prod debug only** and must not
> run in PROD.

> **Known limitations:** WebSocket and background session traffic are not captured (URLSession
> doesn't route them through URLProtocol). `uploadTask(fromFile:)` bodies are not captured.
> Session-level settings (`waitsForConnectivity` etc.) are not carried over to the proxy; cookies
> are preserved via the shared `HTTPCookieStorage`. For very large upload bodies, `capturesBodies:
> false` is recommended (the stream is read into RAM).

## 5. Logging in the app — always through `OlafManager`

App code doesn't connect to `Olaf` directly; it logs through the manager (`trace/debug/info/notice/warning/error/critical`
+ `error(Error)`; the calling file/line is preserved, and it's a no-op in PROD).
```swift
OlafManager.shared.warning("token decode error", category: .security)
OlafManager.shared.error(error, category: .payment, metadata: ["code": code])
```

### Extending categories
Add your project's modules to the `extension LogCategory` block in the integration file:
```swift
public extension LogCategory {
    static let cards: LogCategory = "cards"
    static let transfers: LogCategory = "transfers"
}
```
The file contains `@_exported import Olaf` → call sites can use it without writing `import Olaf`.

---

## 6. Navigation breadcrumb (screen transitions)

`Olaf.trackScreen(_:kind:)` logs screen transitions in the `.navigation` category. The SDK is
**not dependent** on any navigation library (doesn't import into your Coordinator); the host calls
it from its own navigation hook.

### 6.1 Projects using a Coordinator (recommended)
Add a small adapter to the host app (not to Olaf — to the host target):
```swift
import CoordinatorCore   // the host's own navigation package
import Olaf

final class OlafNavigationObserver: CoordinatorActivityObserver {
    func coordinator(willPresentScreen id: String, kind: String) {
        Olaf.trackScreen(id, kind: kind)
    }
    func coordinator(didSwitchRoot id: String) {
        Olaf.trackScreen(id, kind: "root")
    }
    func coordinator(didDismissScreen id: String) {
        Olaf.trackScreen(id, kind: "dismiss")
    }
}
```
Register it with a **single line** in the `AppCoordinator` dispatcher setup (next to existing observers):
```swift
dispatcher.addActivityObserver(OlafNavigationObserver())
```
> If push (NavigationStack) screens don't come through the modal channel: either read
> `topMostViewInfo.screen.id` in the observer's `coordinatorDidObserveUserInteraction()` and call
> `Olaf.trackScreen(..., kind: "push")`, or add a single `notify(kind: "push")` line to the
> `BaseCoordinator` stack's `didSet` (host's choice).

### 6.2 Projects not using a Coordinator (alternative)
Call it manually when a screen appears:
```swift
.onAppear { Olaf.trackScreen("DashboardView", kind: "push") }
```

---

## 7. Verification

1. Build in a config where `#if !PROD` is active (Debug/UAT).
2. Run the app, navigate through a few screens (network/log entries accumulate).
3. **Shake the device** → the viewer opens; app + network logs should appear in a single list.
4. Open a network entry → the status banner, headers, pretty-printed JSON body, and sharing
   (Simple/Full log + cURL) should all work.

> **Version compatibility:** iOS 17+. **No external dependencies.** UIKit code is gated behind
> `#if canImport(UIKit)` (non-UI logic also compiles/tests on macOS).

---

## 8. Bridges (optional)

### 8.1 swift-log backend — `OlafLogHandler` (template)
If the host uses swift-log, copy [`Integration/OlafLogHandler.swift`](Integration/OlafLogHandler.swift)
into the app (since Olaf carries zero dependencies, there's no package dependency on swift-log;
swift-log must already be present in the host project). Then, once at app startup, AFTER
`Olaf.start`:
```swift
LoggingSystem.bootstrap { label in OlafLogHandler(label: label) }
```
All `Logging.Logger` calls in the app and its dependencies will flow into Olaf; the Logger's
`label` becomes the Olaf category, and metadata is preserved.

### 8.2 Importing OSLog
To see `os_log`/`Logger` output from SDKs that don't know about Olaf, in the same list:
```swift
try await Olaf.importOSLogEntries(since: Date().addingTimeInterval(-3600))
```
Also available in the viewer menu: **⋯ → "Import OSLog (1 hour)"**. To keep Olaf's own OSLog
mirror from producing duplicate entries, the main bundle id (the default mirror subsystem) is
automatically excluded; if you gave the mirror a custom `subsystem`, pass it via
`excludingSubsystems:`. Note: entries carry their original timestamp but appear grouped above the
import moment in the list.

---

## 9. Response mocking (optional)

When you don't like an endpoint's response, you can define your own; requests to that URL
**never hit the network** and get your response instead, and the app continues on as if it came
from the real backend (URLSession/Alamofire makes no difference; capture must be set up —
`startAutomaticCapture`/`install`):

```swift
// Empty-list scenario:
OlafNetwork.addMock(OlafMockResponse(urlContains: "/v1/accounts", json: #"{"accounts": []}"#))

// 500 + custom body, POST only:
OlafNetwork.addMock(OlafMockResponse(
    urlContains: "/v1/transfer", method: "POST",
    statusCode: 500, json: #"{"code": "LIMIT_EXCEEDED"}"#
))

// Slow network (3s) + timeout error:
OlafNetwork.addMock(.failure(urlContains: "/v1/rates", error: .timedOut, delaySeconds: 3))

OlafNetwork.removeAllMocks()   // back to the real backend
```

- Matching: if the URL contains the `urlContains` fragment (+ optional `method`); if multiple
  mocks match, the **first one added** wins. Capture URL filters don't affect mocks.
- Mocked requests are logged in the list with a `[mock]` marker; the detail view shows
  "Source: Mock". They sit in the "Active requests" bar for `delaySeconds` (simulating a slow
  network).
- **On-device, without writing code**: in the viewer, a network entry's detail → **"Convert to
  mock"** — the captured response opens in an editor (edit status/body/delay/transport error),
  and it activates once saved. Active mocks can be viewed/deleted from **⋯ → Mocks**.
- Like everything else, this is **non-prod only** (`#if !PROD`).

---

## Adding an external diagnostics tool
Generic handoff is done via `ExternalToolBridge`:
```swift
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, or OlafUI.presentExternal { ... } */ }
}
OlafUI.register(SomeToolBridge())
```
For embeddable SwiftUI tools, use `OlafUI.presentExternal { SomeView() }`; for self-presenting UIKit tools, use
`OlafUI.dismiss()` + the tool's own `show()`.

# Olaf — AI Agent Integration Instructions

When an AI agent receives an "integrate Olaf" command, it follows **this file**. The steps are mechanical and sequential.

## Prerequisites
- Target: an iOS 17+ app.
- Olaf package: `https://github.com/ersel95/olaf`
- Single product: `Olaf` (engine + network capture + viewer all included).
- External diagnostics tools can be added on the host side via the generic `ExternalToolBridge` (the package is not tied to any external tool).

## Steps

### 1. Add the package dependency
Xcode → Add Package → "Choose Package Products":
- To the main app target (and extensions, if needed): `Olaf`.

### 2. Copy the integration file (REQUIRED)
Copy `Integration/OlafIntegration.swift` into the host app's sources (e.g. `Core/Utils/`).
It's the single integration point: `OlafManager` (startup + logging).
Adapt the `// ADAPT:` lines:
- Gating: `#if !PROD` (recommended — capture code doesn't end up in the prod binary) or a runtime feature flag.
- Adjust log categories to match the project.

> The app **does not connect to `Olaf` directly**; logs go through the manager:
> `OlafManager.shared.info("...", category: .auth)`, `OlafManager.shared.error(error, category: .payment)`.
> If Olaf hasn't been started (PROD), calls are no-ops.

### 3. Wire up startup
At the app's entry point — **BEFORE the shared URLSession is set up** (at the start of SwiftUI's
`App.init` or `AppDelegate.didFinishLaunching`, before any session preloading):
```swift
OlafManager.shared.initialize()
```

### 4. If there's a custom Alamofire/URLSession session
If the host sets up its own `URLSessionConfiguration` (deterministic injection instead of automatic swizzling):
add one line when setting up the session:
```swift
OlafManager.shared.configureNetworkCapture(configuration)
```

### 5. Verify
- Build. Shake the device → the Olaf viewer opens.

## Logging (the app always logs through the manager)
Do NOT use `import Olaf` + `Olaf.x(...)` in app code. Use the manager instead:
```swift
OlafManager.shared.info("Login succeeded", category: .auth)
OlafManager.shared.error(error, category: .payment)
```
The manager provides `trace/debug/info/notice/warning/error/critical` + `error(Error)`; the calling file/line is preserved.
Migrate `print()` calls to these methods incrementally.

### Extending categories
Add the project's modules to the `extension LogCategory` block in the integration file:
```swift
public extension LogCategory {
    static let cards: LogCategory = "cards"
    static let transfers: LogCategory = "transfers"
}
```
Since the file contains `@_exported import Olaf`, call sites can use it without writing `import Olaf`.

## Behavior rules (for the agent)
- Do NOT modify the package's `Sources/` contents; integration lives on the host side (only the template + product selection).
- `initialize(...)` must be called BEFORE the shared session; otherwise the first requests may not be captured.
- `Olaf.start(...)` / `initialize(...)` must be called only once.
- Don't tie gating to `#if DEBUG` (TestFlight uses a UAT release config). Use `#if !PROD` or a runtime flag.

## Listing network logs — `OlafNetwork`
**Easiest (no changes to networking code):** already called inside `initialize`:
```swift
OlafNetwork.startAutomaticCapture()   // URLSessionConfiguration swizzle + global; doesn't break SSL
```
Requests/responses land in Olaf raw (unmasked) in the `.network` category. Body + header capture is **on by default**;
to reduce it, use `startAutomaticCapture(OlafNetworkConfiguration(capturesBodies: false))`.
For manual/deterministic injection into your own session (step 4), use `configureNetworkCapture(_:)` / `install(into:chainingTo:)`.

## Extending: adding an external diagnostics tool
To hand off generically, write a type conforming to `ExternalToolBridge` and register it on the host:
```swift
struct SomeToolBridge: ExternalToolBridge {
    let title = "SomeTool"
    @MainActor func open() { /* dismiss + show, or OlafUI.presentExternal { ... } */ }
}
OlafUI.register(SomeToolBridge())
```

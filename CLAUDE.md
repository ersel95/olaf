# Olaf — AI Assistant Notes

A generic, portable Swift **network logger** package: lets you view and share app + network logs
on-device. Fully **local** (no backend, no data is ever sent over the network).

> The bug-reporter/upload mechanism (reporting errors to a backend) that used to be in the package
> has been **deliberately removed** and will be developed in a separate project — summary:
> `docs/bug-reporter-summary.md`.
> It will not be added back to Olaf.

## Repository layout — two platforms, one repo
The Swift package **stays at the repository root** (`Package.swift`, `Sources/`, `Tests/`): SPM
resolves `https://github.com/ersel95/olaf.git` against the root, so moving it into a subdirectory
would break every consumer. The Android port is an independent Gradle build under **`Android/`**,
which no SPM target references — see [`Android/CLAUDE.md`](Android/CLAUDE.md) for its own rules.
Android releases are tagged `android-x.y.z`, keeping the two version lines separate.

## Structure — a SINGLE product, a SINGLE target
SPM offers a single product: `Olaf`. The host adds this one product, and a single `import Olaf` is enough. Folders within the target:
- **`Sources/Olaf/Core`** — the UIKit-free engine: the `Olaf` facade, ring buffer, NDJSON disk
  persistence (per-session history), OSLog bridge, pre-start log buffering. Compiles/tests on every platform.
- **`Sources/Olaf/UI`** — the SwiftUI viewer (shake → list/detail, filter, sharing). All content
  gated behind `#if canImport(UIKit)`. Via the generic `ExternalToolBridge` + `OlafUI.register(_:)`, the host
  can add its own external diagnostics tool to the viewer as a button (the package is not tied to any external tool).
- **`Sources/Olaf/Network`** — URLProtocol network capture; in the `.network` category, raw (unmasked).
  - `startAutomaticCapture(config)` — automatically injects into all sessions via a URLSessionConfiguration swizzle (without touching the host's networking code). Captured requests go through a SINGLE shared proxy session (`OlafProxySession`): connection pooling/TLS are reused, and the shared `HTTPCookieStorage` is preserved. Trust defaults to system validation (`allowsArbitraryServerTrustForCapture` is opt-in only).
  - `OlafNetworkConfiguration`: `capturesBodies/capturesHeaders` (on by default), `includedURLs`/`excludedURLs` (a baseURL allow/deny filter — applied in `canInit`, exclude takes priority), `maxBodyLength`, `category`.
  - JSON bodies are pretty-printed and stored **at capture time**; syntax-highlighted in the viewer via `JSONHighlighter`.

## Build / test
```bash
swift build && swift test                                          # macOS
xcodebuild -scheme Olaf -destination 'generic/platform=iOS' build  # iOS verification
```
Both macOS tests and the iOS build must be green on every change.

## Immutable rules
- **A single SPM product/target remains.** The package is not to be split back into multiple products; upload/bug-reporter is not to be added back.
- **NO redaction/masking/filtering.** All data is stored and displayed **raw**, exactly as it came from the call site (message, metadata, network body/header). Masking is not offered even as an option — the `Redactor`/`BankingRedactor`/`redactionEnabled` API has been deliberately removed; it is not to be added back. Preventing sensitive data leaks is the host's responsibility (gate capture in PROD with `#if !PROD`).
- **The package is NOT tied to any external tool.** External diagnostics tool handoff is added only on the host side via the generic `ExternalToolBridge`
  + `OlafUI.register(_:)`; if needed, another capture tool's URLProtocol can be chained onto the shared session via
  `OlafNetwork.install(chainingTo:)`.
- **Network capture is for non-prod debug only.** The proxy uses system trust validation by default
  (pinning/OS trust is not bypassed); `allowsArbitraryServerTrustForCapture` is opt-in for custom CAs.
  Bodies/headers are logged by default → must not run in PROD (gate via a host runtime flag + `#if !PROD`).
- **Call-site info** (file/line/function) in logging functions must default **directly** to `#fileID/#line/#function`
  — wrapping it in a single struct (LogSource) breaks call-site capture.
- Public repo: bank/company names or internal class names must **not** be added (keep it generic).

## Versioning
SemVer + git tag. Tag when Sources change (`0.x.0`); no tag needed for doc/template-only changes.
`Integration/OlafIntegration.swift` is NOT an SPM product (it's a template copied to the host) — outside of Sources.

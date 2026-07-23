# Olaf Android — AI Assistant Notes

The Android port of the Olaf package. Same product, same decisions, same on-disk schema as the
Swift package at the repository root — expressed in Kotlin and Jetpack Compose. When something is
ambiguous, the iOS source (`../Sources/Olaf/`) is the reference.

## Layout
```
Android/
├── olaf/         # the library
├── olaf-no-op/   # release stand-in: same public API, empty bodies
├── sample/       # demo host; also the API-compatibility check (see below)
└── Integration/  # OlafManager.kt — template copied into host apps, NOT part of the artifact
```

Inside `olaf/src/main/java/com/olaf/`:
- **root package** — the public API: `Olaf`, `OlafConfiguration`, `LogEntry`, `LogLevel`,
  `LogCategory`, formatters. One import for consumers.
- **`internal/`** — engine: runtime, store, NDJSON persistence, Logcat mirror, call-site capture.
- **`network/`** — OkHttp capture, timing listener, mocking.
- **`ui/`** — the Compose viewer (`OlafUI`, the viewer activity, screens, models, exporters).

## Build / test
```bash
./gradlew :olaf:testDebugUnitTest
./gradlew :olaf:assembleRelease :olaf-no-op:assembleRelease
./gradlew :sample:assembleDebug :sample:assembleRelease
```
All three must be green on every change. `allWarningsAsErrors` is on: warnings fail the build.

## Immutable rules
- **NO redaction/masking/filtering.** Message, metadata, bodies and headers are stored and shown
  exactly as they arrived, `Authorization` included. Masking is not offered even as an option;
  preventing leaks is the host's job, which is what `olaf-no-op` exists for.
- **The no-op artifact mirrors the public API exactly.** Every public declaration added to `:olaf`
  must be added to `:olaf-no-op` with the same signature. The sample compiles against `:olaf` in
  debug and `:olaf-no-op` in release, so `:sample:assembleRelease` is the drift alarm — and it is
  the failure mode that otherwise gets noticed last, in someone's production build.
- **On-disk schema stays aligned with iOS**: field names, the level ordinal, the raw category
  string, and the network metadata keys (`url`, `method`, `status`, `durationMs`, `reqBytes`,
  `respBytes`, `reqH.*`, `respH.*`, `t.*`, `mocked`, `cancelled`). Tooling must work against
  either platform's export.
- **The library is not tied to any external tool.** Hand-off happens through the generic
  `ExternalToolBridge` on the host side.
- **Debug-only.** Bodies and headers are captured by default; the artifact split is what keeps it
  out of production.
- Public repo: no bank or company names, no internal class names.

## Deliberate differences from iOS (do not "fix" these)
- **No automatic capture.** OkHttp has no equivalent of the `URLSessionConfiguration` swizzle, so
  the interceptor is added to the client explicitly — as with Chucker. Since there is no proxy
  session re-issuing requests, the host's TLS/pinning applies untouched and iOS's
  `allowsArbitraryServerTrustForCapture` has no counterpart.
- **One `EventListener.Factory` per client** (an OkHttp constraint): `installOlaf(withTiming = false)`
  when the host already has one.
- **Call-site info comes from the stack**, not the compiler, and only for entries actually
  recorded; OkHttp/Okio frames are skipped so requests are attributed to the calling code.

## Versioning
SemVer + git tag `android-x.y.z` (the iOS package keeps its own `x.y.z` line). The version lives in
`Android/build.gradle.kts` (`olafVersion`) and must match the CHANGELOG entry. Tag when sources
change; doc-only changes are not tagged.

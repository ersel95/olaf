<h1 align="center">Olaf for Android</h1>

<p align="center">
  <b>On-device network logger &amp; log viewer for Android.</b><br>
  Shake your device — see every request, response, and log. Nothing ever leaves the device.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Kotlin-2.1-blueviolet.svg" alt="Kotlin 2.1">
  <img src="https://img.shields.io/badge/minSdk-26-blue.svg" alt="minSdk 26">
  <img src="https://img.shields.io/badge/Compose-BOM%202025.09-green.svg" alt="Compose">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey.svg" alt="MIT License"></a>
</p>

> The Android port of the [Olaf iOS package](../README.md). Same product decisions, same on-disk
> schema, same metadata keys — expressed in Kotlin and Jetpack Compose.

> **Olaf is not a proxy and not a crash reporter.** It has **no backend and no telemetry**. Logs are
> stored on-device as NDJSON and shared only when *you* tap share. It also does **not** redact
> anything — data is shown raw, which is exactly why it is a **non-production debug tool** and why
> the release build must use the `olaf-no-op` artifact.

## Features

- [x] **App + network logs in a single timeline** — categories, levels, call-site info, live stream
- [x] **Shake → viewer** — Compose viewer with search, filters, session/history scopes, paginated
      history, pin, and its own activity (your navigation is untouched)
- [x] **Request detail** — status banner, collapsible sections, headers, syntax-highlighted bodies,
      image previews, cURL
- [x] **Body viewer** — full-screen search that keeps JSON blocks whole, line-wrap toggle, copy
- [x] **Timing breakdown** — DNS / TCP / TLS / TTFB per request, protocol (h2/h3), connection reuse
- [x] **Active requests bar** — in-flight calls with elapsed time; spot a hung request instantly
- [x] **Response mocking** — return your own status/body/delay/transport-error without hitting the
      network, or **convert any captured response into a mock** on-device, no code
- [x] **Logcat import** — pull other SDKs' output into the same timeline and the same export
- [x] **Decoding-error capture** — logs the failing field path (`$.user.accounts[0].iban`) next to
      the raw body, folded into the request it belongs to
- [x] **Statistics** — error rate, average/median/p95 durations, status & method distribution,
      slowest requests
- [x] **Export anywhere** — `.log`, raw NDJSON, **HAR 1.2** (Charles/Proxyman/DevTools),
      **Postman Collection v2.1**
- [x] **History across launches** — NDJSON persistence with rotation and retention
- [x] **Zero footprint in release** — the `olaf-no-op` artifact keeps the API but strips everything

## Quick start

```kotlin
// settings.gradle.kts — until the artifacts are published, publish locally with
// `./gradlew publishToMavenLocal` and add mavenLocal() to your repositories.

// build.gradle.kts
debugImplementation("com.github.ersel95.olaf:olaf:0.6.0")
releaseImplementation("com.github.ersel95.olaf:olaf-no-op:0.6.0")
```

```kotlin
// Application.onCreate — before your shared OkHttpClient is built:
Olaf.start(this)
OlafUI.install(this)          // shake → viewer

// Where your OkHttpClient is built:
OkHttpClient.Builder()
    .installOlaf()            // capture + timing
    .build()
```

That's it. Shake the device (or run `adb emu sensor set acceleration 0:0:50` on an emulator) and
the viewer opens. Log your own events too:

```kotlin
Olaf.info("Login succeeded", LogCategory.Auth, mapOf("method" to "biometric"))
Olaf.error(throwable, LogCategory.Payment)
Olaf.debug { "Parsed ${items.size} items" }   // never built when below the threshold
```

For a production-grade setup (an `OlafManager` facade, category conventions, build-type gating),
copy the drop-in template and follow **[INTEGRATION.md](INTEGRATION.md)**. AI agents can follow
**[AGENTS.md](AGENTS.md)**.

## Requirements

| Platform | Kotlin | Dependencies |
|----------|--------|--------------|
| minSdk 26 · compileSdk 36 · Java 17 | 2.1+ | OkHttp, Compose (UI/Material3), Coroutines |

No Hilt, no Room, no reflection, no annotation processing.

## Network capture

```kotlin
OlafNetwork.configuration = OlafNetworkConfiguration(
    includedUrls = listOf("api-gateway"),                            // only your API (empty = all)
    excludedUrls = listOf("firebaseio", "crashlytics", "googleapis") // hide SDK noise
)

OkHttpClient.Builder()
    .addInterceptor(OlafNetwork.interceptor())
    .eventListenerFactory(OlafNetwork.eventListenerFactory())        // timing breakdown
    .build()
```

Requests are logged **raw** under the `network` category. Because the interceptor sits inside the
call chain, your TLS configuration, certificate pinning and timeouts all apply untouched.

### Response mocking

```kotlin
OlafNetwork.addMock(OlafMockResponse(urlContains = "/v1/accounts", json = """{"accounts": []}"""))
OlafNetwork.addMock(OlafMockResponse.failure("/v1/rates", OlafMockResponse.TransportError.Timeout))
```

A matching request never reaches the network; the mock also wins over the capture filters. Manage
active mocks from the viewer's **⋮ → Mocks**.

<details>
<summary><b>Differences from the iOS package</b></summary>

- **No automatic capture.** iOS swizzles `URLSessionConfiguration` and captures every session
  without touching your networking code. OkHttp has no equivalent global hook, so the interceptor
  has to be added to your client — the same single line Chucker requires. In exchange, there is no
  proxy session re-issuing your requests, so `allowsArbitraryServerTrustForCapture` has no
  counterpart: your TLS and pinning setup is simply never bypassed.
- **One event listener per client.** OkHttp allows a single `EventListener.Factory`. If your app
  already installs one, use `installOlaf(withTiming = false)` — everything except the timing
  section keeps working.
- **Call-site info is recovered from the stack** rather than captured at compile time (Kotlin has
  no `#fileID`), and only for entries that are actually recorded. OkHttp/Okio frames are skipped,
  so a captured request is attributed to the code that issued it.
- **Timestamps carry milliseconds**; the reader also accepts the second-precision form iOS writes.

</details>

<details>
<summary><b>Architecture</b></summary>

```
Olaf (facade)
  └─ OlafRuntime            # lifecycle, kill switch, level threshold, pre-start buffer
       └─ LogStore          # single writer thread: ring buffer → disk → Logcat → live flow
            ├─ FilePersistence   # NDJSON, size-based rotation + retention
            ├─ LogFormatter      # plain text / NDJSON export
            └─ LogcatMirror      # android.util.Log bridge

OlafNetwork  ── OlafInterceptor (capture + mocking) + OlafEventListener (timing)
OlafUI       ── OlafViewerActivity (Compose viewer), owns the shake gesture
```

</details>

## Privacy & security

- **Fully local.** No backend, no analytics, no network calls of its own. Data leaves the device
  only through the share sheet, by explicit user action.
- **No redaction, by design.** Everything is stored raw (including `Authorization` and `Cookie`);
  that's what makes it useful for debugging — and why the release build must use `olaf-no-op`.
- The `FileProvider` is declared by the library with an authority derived from your package name,
  and exposes only the export directory.

## Development

```bash
cd Android
./gradlew :olaf:testDebugUnitTest                          # unit tests
./gradlew :olaf:assembleRelease :olaf-no-op:assembleRelease
./gradlew :sample:assembleDebug :sample:assembleRelease     # API compatibility of both artifacts
./gradlew :sample:installDebug                              # try it on a device/emulator
```

101 tests, zero warnings (`allWarningsAsErrors`). See the [CHANGELOG](CHANGELOG.md).

## License

MIT — see [LICENSE](../LICENSE).

# Integrating Olaf into an Android app

A production-grade setup: one integration file, dependency-level gating, and a single line in your
networking code. Roughly 15 minutes.

> The short version lives in the [README](README.md). This document is the one to follow when the
> app is a real product — several flavours, a shared OkHttp client, its own log categories.

---

## 1. Add the dependency

Olaf ships **two artifacts**, wired the same way Chucker is:

```kotlin
// settings.gradle.kts — JitPack builds the artifacts straight from the git tag
repositories {
    google()
    mavenCentral()
    maven { url = uri("https://jitpack.io") }
}
```

```kotlin
// gradle/libs.versions.toml — the version is the tag, so it is always clear
// which commit an artifact came from.
[versions]
olaf = "android-0.10.0"

[libraries]
olaf = { module = "com.github.ersel95.olaf:olaf", version.ref = "olaf" }
olaf-no-op = { module = "com.github.ersel95.olaf:olaf-no-op", version.ref = "olaf" }
```

```kotlin
// the module that owns your OkHttpClient (often :core:data)
debugImplementation(libs.olaf)
releaseImplementation(libs.olaf.no.op)
```

`olaf-no-op` exposes the **same API with empty bodies**, so your code compiles unchanged while no
capture code, no viewer and no stored logs reach the production APK.

### Working against an unreleased change

```bash
cd <olaf-repo>/Android && ./gradlew publishToMavenLocal
```

then add `mavenLocal()` to your repositories and set the version to the local one (`0.8.0`). Same
coordinates, so going back to a released tag is a one-line change.

---

## 2. Copy the integration file (required)

Copy [`Integration/OlafManager.kt`](Integration/OlafManager.kt) into your app (e.g.
`core/common/diagnostics/`) and work through the `// ADAPT:` lines:

- **`isEnabled`** — which builds may run Olaf. `BuildConfig.DEBUG` is the safe default. If you ship
  a non-production *release* flavour (UAT/TST) that should still have Olaf, gate on the flavour —
  but note that a release build links `olaf-no-op`, so it stays a no-op unless you also give that
  flavour the real artifact.
- **`excludedUrls`** — third-party traffic you don't want in the timeline.
- **Categories** — your app's own modules, at the bottom of the file.

> The app **never calls `Olaf` directly**; everything goes through `OlafManager`. That keeps the
> whole integration reviewable in one file, and removable in one commit.

---

## 3. Start it

In `Application.onCreate`, **before the shared OkHttpClient is built**:

```kotlin
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        OlafManager.initialize(this)
    }
}
```

With Hilt, this still belongs in `onCreate` — earlier than any `@Provides` that builds a client.

---

## 4. Wire up the OkHttp client

One line where the client is built:

```kotlin
@Provides
@Singleton
fun provideOkHttpClient(@ApplicationContext context: Context): OkHttpClient =
    with(OkHttpClient.Builder()) {
        // … your existing configuration …
        OlafManager.install(this)      // capture + timing
        build()
    }
```

If the app already sets its own `eventListenerFactory`, keep it and add capture only — OkHttp
allows a single listener per client:

```kotlin
addInterceptor(OlafManager.interceptor())
```

Everything except the timing section keeps working.

### Coexisting with Chucker

They don't conflict: both are ordinary application interceptors. Add Olaf next to Chucker and drop
whichever you stop using.

---

## 5. Verify

1. Build and run a debug build.
2. Trigger some traffic, then shake the device — the viewer opens.
   On an emulator: `adb emu sensor set acceleration 0:0:50`, or call
   `OlafManager.presentViewer(context)` from a developer-settings screen.
3. Requests should appear under the `network` chip, with status, duration and timing.
4. Build a **release** APK and confirm it still compiles — that is the no-op path.

---

## Logging

```kotlin
OlafManager.info("Login succeeded", LogCategory.Auth, mapOf("method" to "biometric"))
OlafManager.error(throwable, LogCategory.Payment)
```

Migrate `Log.d` / `Timber` calls over incrementally. Call-site information (file, line, function) is
captured automatically.

### Already using Timber? Bridge it instead of migrating

Copy [`Integration/OlafTimberTree.kt`](Integration/OlafTimberTree.kt) and plant it next to your
debug tree:

```kotlin
Timber.plant(Timber.DebugTree())   // Logcat keeps working
Timber.plant(OlafTimberTree())     // …and the same lines land in the viewer
```

Every `Timber` call in the app — and in any library that logs through Timber — now shows up in
Olaf, with the Timber tag as the category. This is the counterpart of the iOS package's swift-log
handler, and it means no call site has to change at all.

### Screen breadcrumbs

From your navigation observer:

```kotlin
OlafManager.trackScreen("dashboard")
OlafManager.trackScreen("paymentSheet", kind = "sheet")
```

### Decoding errors

Wherever you parse a response, report the failure with the body that caused it:

```kotlin
val accounts = OlafDecoding.decode(
    url = response.request.url.toString(),
    body = body,
    typeName = "AccountsResponse"
) {
    gson.fromJson(body, AccountsResponse::class.java)
}
```

`OlafDecoding.decode` logs the failure and rethrows it untouched, so behaviour is unchanged — and
because it takes a lambda it works with Gson, Moshi or kotlinx.serialization alike. Reporting it
manually works too:

```kotlin
OlafManager.logDecodingError(error, url = url, body = body, typeName = "AccountsResponse")
```

The failing field path (`$.accounts[0].iban`) is lifted out of the Gson/Moshi message, and the entry
is folded into the request it belongs to — the list shows a single network row, the detail lists the
decode failures.

---

## Response mocking

```kotlin
OlafNetwork.addMock(OlafMockResponse(urlContains = "/v1/accounts", json = """{"accounts": []}"""))
OlafNetwork.addMock(
    OlafMockResponse.failure("/v1/rates", OlafMockResponse.TransportError.Timeout, delayMillis = 3_000)
)
```

A matching request never reaches the network, and mocks take priority over the capture filters.
Manage them at runtime from the viewer's **⋮ → Mocks**.

---

## Rules

- `initialize` must run **before** the shared client is built, or the first requests are missed.
- Do **not** enable Olaf for the production flavour. Bodies and headers — `Authorization` included
  — are stored raw, by design; preventing leaks is the host's job.
- Do not modify the library's sources; the integration lives on the host side.
- Every new method added to `OlafManager` must work in release too — that is, it must exist in the
  no-op artifact.

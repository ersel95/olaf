# Olaf Android — AI agent integration instructions

When an AI agent is told to "integrate Olaf" into an Android app, it follows **this file**. The
steps are mechanical and sequential; human-facing rationale lives in [INTEGRATION.md](INTEGRATION.md).

## Prerequisites
- Target: an Android app with `minSdk ≥ 26` that uses OkHttp.
- Two artifacts: `com.github.ersel95.olaf:olaf` (debug) and `:olaf-no-op` (release).
- The library needs no Hilt, Room, annotation processing or reflection.

---

## Step 1 — Repository

Artifacts are built from the git tag by JitPack, so the repository has to be declared. In
`settings.gradle.kts` (or the project's `build.gradle.kts` if it still uses `allprojects`):

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }   // ← required for Olaf
    }
}
```

**Skipping this is the most common failure**: without it, the dependency cannot resolve at all.

If the project sets `repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)`, the line must
go in `dependencyResolutionManagement`, not in a module.

## Step 2 — Dependency

The version **is** the git tag. Latest: `android-0.10.0`
(check <https://github.com/ersel95/olaf/releases> for newer).

With a version catalog (`gradle/libs.versions.toml`):

```toml
[versions]
olaf = "android-0.10.0"

[libraries]
olaf = { module = "com.github.ersel95.olaf:olaf", version.ref = "olaf" }
olaf-no-op = { module = "com.github.ersel95.olaf:olaf-no-op", version.ref = "olaf" }
```

Then, in the module that owns the `OkHttpClient` (often `:core:data`):

```kotlin
debugImplementation(libs.olaf)
releaseImplementation(libs.olaf.no.op)
```

Without the catalog:

```kotlin
debugImplementation("com.github.ersel95.olaf:olaf:android-0.10.0")
releaseImplementation("com.github.ersel95.olaf:olaf-no-op:android-0.10.0")
```

**Add both.** Only the debug artifact → release builds fail to compile. Only the no-op → nothing
is ever captured.

## Step 3 — Copy the integration file (REQUIRED)

Copy [`Integration/OlafManager.kt`](Integration/OlafManager.kt) into the host app (e.g.
`core/data/.../diagnostics/`) and work through every `// ADAPT:` line:

- the `package` declaration,
- `isEnabled` — which builds may run Olaf,
- `excludedUrls` — third-party traffic to keep out of the timeline,
- the log categories at the bottom of the file.

The app calls `OlafManager`, never `Olaf` directly.

## Step 4 — Start it

In `Application.onCreate`, **before any `OkHttpClient` is constructed**:

```kotlin
OlafManager.initialize(this)
```

With Hilt this still belongs in `onCreate`, ahead of any `@Provides` that builds a client.

## Step 5 — Wire the client

Where the shared client is built:

```kotlin
OlafManager.install(builder)          // capture + timing breakdown
```

If the app already sets its own `eventListenerFactory`, keep it and add capture only — OkHttp
allows a single listener per client:

```kotlin
builder.addInterceptor(OlafManager.interceptor())
```

Coexists with Chucker: both are ordinary application interceptors.

## Step 6 — Optional but recommended

**Already using Timber?** Copy [`Integration/OlafTimberTree.kt`](Integration/OlafTimberTree.kt)
and plant it — every existing `Timber` call then lands in the viewer, with no call site changed:

```kotlin
Timber.plant(Timber.DebugTree())
Timber.plant(OlafTimberTree())
```

**Notification permission (Android 13+).** Olaf declares `POST_NOTIFICATIONS` and shows captured
requests in the shade, with a tap into the viewer. Requesting the runtime permission is the host's
call; without it Olaf stays quiet and everything else still works.

**Decoding errors.** Where responses are parsed:

```kotlin
val model = OlafDecoding.decode(url = url, body = body, typeName = "AccountsResponse") {
    gson.fromJson(body, AccountsResponse::class.java)
}
```

## Step 7 — Verify

1. `./gradlew :app:assembleDebug` **and** `assembleRelease` must both compile — the second one
   exercises the no-op path, and is where a missing `releaseImplementation` shows up.
2. Run a debug build, trigger a request, then shake the device (emulator:
   `adb emu sensor set acceleration 0:0:50`) or tap the capture notification. The viewer opens
   with the request listed under the `network` chip, with status, duration and timing.

---

## Behaviour rules (for the agent)

- Do **not** modify the library's sources; integration happens on the host side only.
- Do **not** enable Olaf for the production flavour — bodies and headers, `Authorization`
  included, are stored raw by design. That is what the no-op artifact protects against.
- `initialize` must precede the shared client, or the first requests are missed.
- Anything added to `OlafManager` must also exist in the no-op artifact, or **only the release
  build** breaks — the failure mode that gets noticed last.
- Do not add the repository or the dependency to a module when the project uses
  `FAIL_ON_PROJECT_REPOS`; it belongs in `dependencyResolutionManagement`.

## Extending categories

Add the project's modules as companion extensions, so call sites read like the built-ins:

```kotlin
val LogCategory.Companion.Transfers: LogCategory get() = LogCategory("transfers")
// call site: OlafManager.info("…", LogCategory.Transfers)
```

## Adding an external diagnostics tool

Olaf is tied to no external tool. To hand off to one, implement `ExternalToolBridge` on the host
side and register it:

```kotlin
OlafUI.register(object : ExternalToolBridge {
    override val title = "SomeTool"
    override fun open(context: Context) { SomeTool.show(context) }
})
```

To make the viewer's logo hand off instead, use `OlafManager.setLogoTapHandler { … }`.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Could not find com.github.ersel95.olaf:olaf` | The JitPack repository is missing (Step 1) |
| Release build fails, debug is fine | `releaseImplementation(libs.olaf.no.op)` is missing |
| Viewer opens but is empty | `OlafManager.install(builder)` was never applied to the client that makes the calls |
| First requests missing | `initialize` runs after the client is built |
| No timing section | The app installs its own `EventListener.Factory`; use `interceptor()` alone |
| Nothing in the notification shade | `POST_NOTIFICATIONS` not granted (Android 13+) |

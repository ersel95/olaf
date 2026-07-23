# Olaf Android — AI agent integration instructions

When an AI agent is told to "integrate Olaf" into an Android app, it follows **this file**. The
steps are mechanical and sequential. Human-facing detail lives in [INTEGRATION.md](INTEGRATION.md).

## Prerequisites
- Target: an Android app with minSdk ≥ 26 and OkHttp.
- Two artifacts: `com.github.ersel95.olaf:olaf` (debug) and `:olaf-no-op` (release).
- No Hilt, Room or annotation processing is required by the library.

## Steps

### 1. Add the dependency
Add both artifacts to the module that owns the `OkHttpClient` (often `:core:data`), using the
version catalog if the project has one:

```kotlin
debugImplementation(libs.olaf)
releaseImplementation(libs.olaf.no.op)
```

Never add only one of them: without the no-op, release builds fail to compile.

### 2. Copy the integration file (REQUIRED)
Copy `Integration/OlafManager.kt` into the host app and adapt every `// ADAPT:` line — package,
`isEnabled`, `excludedUrls`, categories. This is the single integration point.

### 3. Start it
In `Application.onCreate`, before any `OkHttpClient` is constructed:

```kotlin
OlafManager.initialize(this)
```

### 4. Wire the client
Where the shared client is built:

```kotlin
OlafManager.install(builder)          // capture + timing
```

If the app already sets an `eventListenerFactory`, use `OlafManager.interceptor()` instead and
leave the listener alone — OkHttp permits only one per client.

### 5. Verify
- `assembleDebug` **and** `assembleRelease` must both compile — the second one exercises the no-op.
- Run a debug build, make a request, shake the device: the viewer opens with the request listed.

## Behaviour rules (for the agent)
- Do **not** modify the library's sources. Integration happens on the host side only.
- Do **not** enable Olaf for the production flavour — bodies and headers are stored raw by design.
- App code calls `OlafManager`, never `Olaf` directly.
- `initialize` must precede the shared client, or early requests are missed.
- Anything added to `OlafManager` must also exist in the no-op artifact, or only the release build
  breaks — which is the failure mode that gets noticed last.

## Extending categories
Add the project's modules as companion extensions, so call sites read like the built-ins:

```kotlin
val LogCategory.Companion.Transfers: LogCategory get() = LogCategory("transfers")
// call site: OlafManager.info("…", LogCategory.Transfers)
```

## Adding an external diagnostics tool
Olaf is not tied to any external tool. To hand off to one, implement `ExternalToolBridge` on the
host side and register it:

```kotlin
OlafUI.register(object : ExternalToolBridge {
    override val title = "SomeTool"
    override fun open(context: Context) { SomeTool.show(context) }
})
```

To make the viewer's title hand off instead, use `OlafManager.setLogoTapHandler { … }`.

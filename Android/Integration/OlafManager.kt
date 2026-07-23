package com.example.diagnostics // ADAPT: your app's package

import android.app.Application
import android.content.Context
import com.olaf.LogCategory
import com.olaf.Olaf
import com.olaf.OlafConfiguration
import com.olaf.network.OlafNetwork
import com.olaf.network.OlafNetworkConfiguration
import com.olaf.ui.OlafUI
import okhttp3.Interceptor
import okhttp3.OkHttpClient

/**
 * Single integration point for Olaf (in-app log & network viewer).
 *
 * The app never calls `Olaf` directly — it goes through this manager, so the whole integration
 * (gating, categories, capture filters) lives in one file that is easy to review and easy to rip
 * out.
 *
 * ## Gating
 * There is no `#if` in Kotlin; gating is done at the **dependency** level, exactly like Chucker:
 *
 * ```kotlin
 * debugImplementation("com.github.ersel95.olaf:olaf:x.y.z")
 * releaseImplementation("com.github.ersel95.olaf:olaf-no-op:x.y.z")
 * ```
 *
 * In release the no-op artifact provides the same API with empty bodies, so this file compiles
 * unchanged while no capture code, no viewer and no stored logs reach the production APK.
 *
 * If your app ships a non-production **release** flavour (UAT/TST) that should still have Olaf,
 * gate on the flavour instead — see [isEnabled].
 */
object OlafManager {

    // ADAPT: which builds may run Olaf. Never leave it enabled for the production flavour: bodies
    // and headers — including Authorization — are stored raw, by design.
    private val isEnabled: Boolean
        get() = BuildConfig.DEBUG // ADAPT: e.g. `BuildConfig.DEBUG || BuildConfig.FLAVOR_default != "PROD"`

    // ADAPT: third-party traffic you don't want in the timeline.
    private val networkConfiguration = OlafNetworkConfiguration(
        excludedUrls = listOf(
            "firebaseio",
            "crashlytics",
            "googleapis",
            "app-measurement",
            "firebaseinstallations",
            "firebaseremoteconfig"
        )
    )

    /**
     * Call from `Application.onCreate`, **before** the shared OkHttpClient is built — otherwise
     * the earliest requests are not captured. Safe to call more than once.
     */
    fun initialize(application: Application) {
        if (!isEnabled) return

        Olaf.start(application, OlafConfiguration())
        OlafNetwork.configuration = networkConfiguration
        OlafUI.install(application) // shake → viewer
    }

    /**
     * Add to your `OkHttpClient.Builder`. Returns a pass-through interceptor when Olaf is
     * disabled, so the call site needs no conditional.
     */
    fun interceptor(): Interceptor =
        if (isEnabled) OlafNetwork.interceptor() else Interceptor { it.proceed(it.request()) }

    /**
     * Installs capture **and** the timing breakdown in one call. Use this unless the app already
     * sets its own `eventListenerFactory` — OkHttp allows only one, and Olaf's would replace it.
     */
    fun install(builder: OkHttpClient.Builder): OkHttpClient.Builder {
        if (!isEnabled) return builder
        return builder
            .addInterceptor(OlafNetwork.interceptor())
            .eventListenerFactory(OlafNetwork.eventListenerFactory())
    }

    /** Opens the viewer programmatically (e.g. from a developer-settings screen). */
    fun presentViewer(context: Context) {
        if (isEnabled) OlafUI.present(context)
    }

    /**
     * Turns the viewer's title into a hand-off button — for apps that also ship another
     * shake-activated diagnostics tool. Pass `null` to remove it.
     */
    fun setLogoTapHandler(handler: (() -> Unit)?) {
        if (isEnabled) OlafUI.onLogoTap(handler)
    }

    // MARK: - Logging
    //
    // The app logs through these, never through `Olaf` directly. Migrate `Log.d`/`Timber` calls
    // over incrementally.

    fun trace(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        Olaf.trace(message, category, metadata)

    fun debug(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        Olaf.debug(message, category, metadata)

    fun info(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        Olaf.info(message, category, metadata)

    fun notice(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        Olaf.notice(message, category, metadata)

    fun warning(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        Olaf.warning(message, category, metadata)

    fun error(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        Olaf.error(message, category, metadata)

    fun error(throwable: Throwable, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        Olaf.error(throwable, category, metadata)

    fun critical(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        Olaf.critical(message, category, metadata)

    /** Screen transition breadcrumb — call it from your navigation observer. */
    fun trackScreen(name: String, kind: String = "push") = Olaf.trackScreen(name, kind)

    /** Report a deserialization failure with the offending field path and the raw body. */
    fun logDecodingError(error: Throwable, url: String? = null, body: String? = null, typeName: String? = null) =
        Olaf.logDecodingError(error, url, body, typeName)
}

// ADAPT: your app's own categories. Because these are extensions on the companion, call sites read
// exactly like the built-in ones: `LogCategory.Transfers`.
val LogCategory.Companion.Dashboard: LogCategory get() = LogCategory("dashboard")
val LogCategory.Companion.Accounts: LogCategory get() = LogCategory("accounts")
val LogCategory.Companion.Transfers: LogCategory get() = LogCategory("transfers")

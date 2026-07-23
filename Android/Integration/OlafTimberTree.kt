package com.example.diagnostics // ADAPT: your app's package

import android.util.Log
import com.olaf.LogCategory
import com.olaf.LogLevel
import com.olaf.Olaf
import timber.log.Timber

/**
 * DROP-IN TEMPLATE — not part of the Olaf artifact.
 *
 * Bridges [Timber] into Olaf: once planted, **every** `Timber.d/i/w/e` call in the app and in any
 * library that logs through Timber lands in the viewer, with the Timber tag becoming the Olaf
 * category. The Android counterpart of the iOS package's swift-log handler.
 *
 * Olaf deliberately carries no dependency on Timber — copy this file into the host app instead.
 *
 * ```kotlin
 * // Application.onCreate, after OlafManager.initialize(this):
 * if (BuildConfig.DEBUG) {
 *     Timber.plant(Timber.DebugTree())   // keep the console output
 *     Timber.plant(OlafTimberTree())     // and mirror it into Olaf
 * }
 * ```
 *
 * Planting this alongside `DebugTree` is the usual setup: Logcat keeps working, and the same lines
 * become searchable, filterable and shareable in the viewer.
 */
class OlafTimberTree(
    /** Category used when a log call carries no tag. */
    private val defaultCategory: LogCategory = LogCategory.General
) : Timber.Tree() {

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        val category = tag?.takeIf { it.isNotBlank() }?.let { LogCategory(it.lowercase()) }
            ?: defaultCategory

        val metadata = buildMap {
            tag?.let { put("tag", it) }
            t?.let {
                put("errorType", it.javaClass.name)
                put("errorDetail", it.stackTraceToString())
            }
        }

        Olaf.log(priority.toOlafLevel(), message, category, metadata)
    }

    private fun Int.toOlafLevel(): LogLevel = when (this) {
        Log.VERBOSE -> LogLevel.TRACE
        Log.DEBUG -> LogLevel.DEBUG
        Log.INFO -> LogLevel.INFO
        Log.WARN -> LogLevel.WARNING
        Log.ERROR -> LogLevel.ERROR
        Log.ASSERT -> LogLevel.CRITICAL
        else -> LogLevel.INFO
    }
}

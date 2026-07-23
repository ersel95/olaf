package com.olaf

/**
 * Log severity level. Aligned with the iOS package's level model, and with `android.util.Log`
 * on the mirroring side.
 *
 * The ordinal is the on-disk representation (`trace = 0` … `critical = 6`), which is what the
 * iOS package writes into NDJSON too — so history files stay readable across both platforms.
 */
enum class LogLevel {
    TRACE,
    DEBUG,
    INFO,
    NOTICE,
    WARNING,
    ERROR,
    CRITICAL;

    /** Symbol used to tell levels apart at a glance in the viewer. */
    val symbol: String
        get() = when (this) {
            TRACE -> "🔬"
            DEBUG -> "🐞"
            INFO -> "ℹ️"
            NOTICE -> "📌"
            WARNING -> "⚠️"
            ERROR -> "❌"
            CRITICAL -> "🔥"
        }

    companion object {
        /** Reads a level back from its on-disk ordinal; unknown values fall back to [INFO]. */
        fun fromOrdinal(value: Int): LogLevel = entries.getOrElse(value) { INFO }
    }
}

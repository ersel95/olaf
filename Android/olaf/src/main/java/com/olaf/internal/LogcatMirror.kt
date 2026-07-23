package com.olaf.internal

import android.util.Log
import com.olaf.LogEntry
import com.olaf.LogLevel

/**
 * Mirrors entries to Logcat, so they also show up in `adb logcat` and the IDE console —
 * the Android counterpart of the iOS package's OSLog bridge.
 *
 * Only ever called from [LogStore]'s single writer thread.
 */
internal class LogcatMirror(private val tagPrefix: String) {

    fun log(entry: LogEntry) {
        val tag = "$tagPrefix/${entry.category.rawValue}"
        when (entry.level) {
            LogLevel.TRACE, LogLevel.DEBUG -> Log.d(tag, entry.message)
            LogLevel.INFO, LogLevel.NOTICE -> Log.i(tag, entry.message)
            LogLevel.WARNING -> Log.w(tag, entry.message)
            // CRITICAL deliberately uses Log.e rather than Log.wtf: on some builds `wtf` is
            // wired to terminate the process, which a logging tool must never cause.
            LogLevel.ERROR, LogLevel.CRITICAL -> Log.e(tag, entry.message)
        }
    }
}

package com.olaf.ui.util

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Small display helpers shared by the viewer's screens. */
internal object Formatting {

    private val timeFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("HH:mm:ss.SSS").withZone(ZoneId.systemDefault())

    private val dateTimeFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm:ss").withZone(ZoneId.systemDefault())

    fun time(instant: Instant): String = timeFormatter.format(instant)

    fun dateTime(instant: Instant): String = dateTimeFormatter.format(instant)

    /** Human-readable byte count, e.g. `1.2 KB`. */
    fun byteCount(bytes: Long): String = when {
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> String.format(Locale.US, "%.1f KB", bytes / 1024.0)
        else -> String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024))
    }

    fun duration(millis: Long): String = when {
        millis < 1000 -> "${millis}ms"
        else -> String.format(Locale.US, "%.2fs", millis / 1000.0)
    }
}

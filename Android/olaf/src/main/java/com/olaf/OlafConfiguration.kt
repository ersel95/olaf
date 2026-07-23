package com.olaf

/**
 * Configuration for the Olaf core. Supplied once via [Olaf.start].
 */
data class OlafConfiguration(

    /** Logs below this level are ignored entirely (the message lambda is never invoked). */
    val minimumLevel: LogLevel = LogLevel.TRACE,

    /** In-memory ring buffer capacity (the newest N entries stay in RAM). */
    val inMemoryCapacity: Int = 2000,

    /** Should logs also be written to disk, so history survives a restart? */
    val persistsToDisk: Boolean = true,

    /** The active log file is rotated once it exceeds this size, in bytes. */
    val maxFileSize: Int = 1_048_576, // 1 MB

    /** Maximum number of log files kept on disk (the oldest are deleted). */
    val maxFileCount: Int = 5,

    /**
     * Discard rotated files older than this, in milliseconds. Applied alongside [maxFileCount]:
     * whichever limit bites first wins, so a quiet week can't leave stale logs on disk and a busy
     * hour can't blow past the file cap. `0` disables the age limit.
     */
    val retentionMillis: Long = 24 * 60 * 60 * 1000L, // 1 day

    /**
     * **Human-readable** format used for `.log` export. On-disk storage is always NDJSON, so
     * history round-trips losslessly; this formatter only shapes the shared text.
     */
    val exportFormatter: LogFormatter = PlainTextFormatter(),

    /** Mirror entries to Logcat, so they show up in `adb logcat` / the IDE console. */
    val mirrorsToLogcat: Boolean = true,

    /**
     * Show captured requests in the notification shade, with a tap straight into the viewer, and
     * register a launcher shortcut. Silently inert without the notification permission.
     */
    val showsNotification: Boolean = true,

    /** Logcat tag prefix; the category is appended (`Olaf/network`). */
    val logcatTag: String = "Olaf"
) {
    init {
        require(inMemoryCapacity > 0) { "inMemoryCapacity must be positive" }
    }

    /** Values are clamped rather than rejected, so a bad config can never disable logging. */
    internal val effectiveMaxFileSize: Int get() = maxOf(4096, maxFileSize)
    internal val effectiveMaxFileCount: Int get() = maxOf(1, maxFileCount)
}

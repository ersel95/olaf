package com.olaf

import android.content.Context
import com.olaf.internal.CallSite
import com.olaf.internal.OlafRuntime
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import java.io.File
import java.time.Instant

/**
 * Olaf's public facade — one-line setup plus an ergonomic logging API.
 *
 * ```kotlin
 * Olaf.start(context)
 * Olaf.info("Login succeeded", LogCategory.Auth, mapOf("method" to "biometric"))
 * Olaf.error(throwable, LogCategory.Payment)
 * ```
 *
 * Every level also has a lambda form, so a message that would be expensive to build is never
 * built when the entry would be dropped:
 *
 * ```kotlin
 * Olaf.debug { "Parsed ${items.size} items: ${items.joinToString()}" }
 * ```
 */
object Olaf {

    internal val runtime = OlafRuntime()

    // MARK: - Setup

    /**
     * Starts Olaf. Idempotent — the first call wins.
     *
     * Call it before the app's shared OkHttp client is built, so the earliest requests are
     * captured too.
     */
    fun start(context: Context, configuration: OlafConfiguration = OlafConfiguration()) {
        runtime.start(context, configuration)
    }

    /** Full runtime on/off switch. While disabled no log is processed at all. */
    var isEnabled: Boolean
        get() = runtime.isEnabled
        set(value) {
            runtime.isEnabled = value
        }

    /** Has Olaf been started? */
    val isStarted: Boolean get() = runtime.isStarted

    /**
     * Collection threshold: logs below this level are never processed — the message lambda isn't
     * even invoked. Seeded from the start configuration and changeable at runtime (e.g. to cut
     * noise down to "warnings and above"). Not persisted; scoped to the process lifetime.
     */
    var minimumLevel: LogLevel
        get() = runtime.minimumLevel
        set(value) {
            runtime.minimumLevel = value
        }

    /** Identifier of the current app session — a new one per [start]. Groups history by session. */
    val currentSessionId: String get() = runtime.currentSessionId

    // MARK: - Log API

    fun log(
        level: LogLevel,
        message: String,
        category: LogCategory = LogCategory.General,
        metadata: Map<String, String> = emptyMap()
    ) {
        log(level, category, metadata) { message }
    }

    fun log(
        level: LogLevel,
        category: LogCategory = LogCategory.General,
        metadata: Map<String, String> = emptyMap(),
        message: () -> String
    ) {
        when (val target = runtime.target(level)) {
            is OlafRuntime.LogTarget.Drop -> return

            is OlafRuntime.LogTarget.Store -> {
                val site = CallSite.capture()
                target.store.ingest(
                    date = Instant.now(),
                    level = level,
                    category = category,
                    message = message(),
                    metadata = metadata,
                    file = site.file,
                    line = site.line,
                    function = site.function,
                    thread = Thread.currentThread().name
                )
            }

            is OlafRuntime.LogTarget.Buffer -> {
                val site = CallSite.capture()
                runtime.buffer(
                    date = Instant.now(),
                    level = level,
                    category = category,
                    message = message(),
                    metadata = metadata,
                    file = site.file,
                    line = site.line,
                    function = site.function,
                    thread = Thread.currentThread().name
                )
            }
        }
    }

    fun trace(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        log(LogLevel.TRACE, message, category, metadata)

    fun trace(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) =
        log(LogLevel.TRACE, category, metadata, message)

    fun debug(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        log(LogLevel.DEBUG, message, category, metadata)

    fun debug(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) =
        log(LogLevel.DEBUG, category, metadata, message)

    fun info(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        log(LogLevel.INFO, message, category, metadata)

    fun info(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) =
        log(LogLevel.INFO, category, metadata, message)

    fun notice(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        log(LogLevel.NOTICE, message, category, metadata)

    fun notice(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) =
        log(LogLevel.NOTICE, category, metadata, message)

    fun warning(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        log(LogLevel.WARNING, message, category, metadata)

    fun warning(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) =
        log(LogLevel.WARNING, category, metadata, message)

    fun error(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        log(LogLevel.ERROR, message, category, metadata)

    fun error(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) =
        log(LogLevel.ERROR, category, metadata, message)

    fun critical(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) =
        log(LogLevel.CRITICAL, message, category, metadata)

    fun critical(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) =
        log(LogLevel.CRITICAL, category, metadata, message)

    /**
     * Logs a [Throwable] directly: the message is its own message (falling back to the class
     * name), and type/detail land in metadata.
     */
    fun error(
        throwable: Throwable,
        category: LogCategory = LogCategory.General,
        metadata: Map<String, String> = emptyMap()
    ) {
        val enriched = metadata + mapOf(
            "errorType" to throwable.javaClass.name,
            "errorDetail" to throwable.stackTraceToString()
        )
        log(LogLevel.ERROR, throwable.message ?: throwable.javaClass.simpleName, category, enriched)
    }

    // MARK: - Navigation tracking

    /**
     * Logs a screen transition under [LogCategory.Navigation]. Deliberately string-based: Olaf is
     * not tied to any navigation library — the host calls this from its own navigation hook.
     *
     * ```kotlin
     * Olaf.trackScreen("dashboard")
     * Olaf.trackScreen("paymentSheet", kind = "sheet")
     * ```
     */
    fun trackScreen(name: String, kind: String = "push") {
        log(
            level = LogLevel.INFO,
            message = name,
            category = LogCategory.Navigation,
            metadata = mapOf("screen" to name, "kind" to kind)
        )
    }

    // MARK: - Reading & management (this is what feeds the viewer)

    /** An instant copy of the entries currently in memory for this session, oldest to newest. */
    fun snapshot(): List<LogEntry> = runtime.store()?.snapshot().orEmpty()

    /** Non-blocking [snapshot] — the viewer uses this so the main thread never waits on a write burst. */
    suspend fun snapshotAsync(): List<LogEntry> = runtime.store()?.snapshotAsync().orEmpty()

    /**
     * Every entry on disk, **including previous sessions**. For large histories prefer the
     * paginated [loadPersistedPage] so the whole history isn't held in memory at once.
     */
    suspend fun loadPersistedEntries(): List<LogEntry> = runtime.store()?.loadPersisted().orEmpty()

    /**
     * Reads on-disk history **paginated**, newest to oldest. Pass `cursor = null` for the first
     * page, then the previous page's [PersistedLogPage.nextCursor] for the next (older) one; a
     * `null` cursor coming back means the end of history.
     */
    suspend fun loadPersistedPage(cursor: String? = null, minimumEntries: Int = 500): PersistedLogPage =
        runtime.store()?.loadPersistedPage(cursor, minimumEntries)
            ?: PersistedLogPage(emptyList(), null)

    /** A stream that live-broadcasts new entries. */
    fun stream(): Flow<LogEntry> = runtime.store()?.stream ?: emptyFlow()

    /** Clears all logs — memory and disk. */
    fun clear() {
        runtime.store()?.clear()
    }

    // MARK: - Export

    /** Merges all on-disk logs into a single shareable `.log` file. */
    suspend fun exportFile(): File? = runtime.store()?.exportFile()

    /**
     * Writes the given entries to a shareable `.log` file. The viewer uses this to share the
     * currently **filtered** list; which entries to include is up to the caller.
     */
    suspend fun exportFile(entries: List<LogEntry>): File? = runtime.store()?.exportFile(entries)

    /**
     * Writes the given entries as **raw NDJSON** (one JSON [LogEntry] per line) — the same schema
     * as the on-disk format, so it can be fed losslessly into `jq` or other tooling.
     */
    suspend fun exportNdjsonFile(entries: List<LogEntry>): File? =
        runtime.store()?.exportNdjsonFile(entries)
}

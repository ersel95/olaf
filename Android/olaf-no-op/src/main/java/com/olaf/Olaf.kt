package com.olaf

import android.content.Context
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import java.io.File
import java.time.Instant

/*
 * No-op counterpart of the Olaf facade — the release stand-in wired up as
 * `releaseImplementation("com.github.ersel95.olaf:olaf-no-op:x.y.z")`.
 *
 * It mirrors the real public surface **exactly**, with empty bodies, so call sites compile
 * unchanged while no capture code, no viewer and no stored data reach the production APK.
 *
 * Every public declaration added to `:olaf` must be added here with the same signature, or the
 * release build — and only the release build — breaks.
 */

/** No-op stand-in. See the real implementation in the `olaf` artifact. */
enum class LogLevel {
    TRACE, DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL;

    val symbol: String get() = ""

    companion object {
        fun fromOrdinal(value: Int): LogLevel = INFO
    }
}

/** No-op stand-in. */
@JvmInline
value class LogCategory(val rawValue: String) {

    override fun toString(): String = rawValue

    companion object {
        val General = LogCategory("general")
        val Auth = LogCategory("auth")
        val Payment = LogCategory("payment")
        val Network = LogCategory("network")
        val Session = LogCategory("session")
        val Security = LogCategory("security")
        val Navigation = LogCategory("navigation")
        val Logcat = LogCategory("logcat")
        val Decoding = LogCategory("decoding")
    }
}

/** No-op stand-in. */
data class LogEntry(
    val id: String = "",
    val date: Instant = Instant.EPOCH,
    val level: LogLevel = LogLevel.INFO,
    val category: LogCategory = LogCategory.General,
    val message: String = "",
    val metadata: Map<String, String> = emptyMap(),
    val file: String = "",
    val line: Int = 0,
    val function: String = "",
    val thread: String = "",
    val sessionId: String = ""
) {
    val fileName: String get() = ""
}

/** No-op stand-in. */
data class PersistedLogPage(
    val entries: List<LogEntry> = emptyList(),
    val nextCursor: String? = null
)

/** No-op stand-in. */
fun interface LogFormatter {
    fun format(entry: LogEntry): String
}

/** No-op stand-in. */
class PlainTextFormatter(
    private val includesMetadata: Boolean = true,
    private val includesSource: Boolean = true
) : LogFormatter {
    override fun format(entry: LogEntry): String = ""
}

/** No-op stand-in. */
class JsonLogFormatter : LogFormatter {
    override fun format(entry: LogEntry): String = ""
}

/** No-op stand-in. */
data class OlafConfiguration(
    val minimumLevel: LogLevel = LogLevel.TRACE,
    val inMemoryCapacity: Int = 2000,
    val persistsToDisk: Boolean = true,
    val maxFileSize: Int = 1_048_576,
    val maxFileCount: Int = 5,
    val exportFormatter: LogFormatter = PlainTextFormatter(),
    val mirrorsToLogcat: Boolean = true,
    val logcatTag: String = "Olaf"
)

/**
 * No-op facade. Every call is a no-op and every read returns an empty value; the message lambdas
 * are never invoked, so building a log message costs nothing in release either.
 */
object Olaf {

    fun start(context: Context, configuration: OlafConfiguration = OlafConfiguration()) = Unit

    var isEnabled: Boolean
        get() = false
        set(_) = Unit

    val isStarted: Boolean get() = false

    var minimumLevel: LogLevel
        get() = LogLevel.TRACE
        set(_) = Unit

    val currentSessionId: String get() = ""

    fun log(
        level: LogLevel,
        message: String,
        category: LogCategory = LogCategory.General,
        metadata: Map<String, String> = emptyMap()
    ) = Unit

    fun log(
        level: LogLevel,
        category: LogCategory = LogCategory.General,
        metadata: Map<String, String> = emptyMap(),
        message: () -> String
    ) = Unit

    fun trace(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) = Unit
    fun trace(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) = Unit

    fun debug(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) = Unit
    fun debug(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) = Unit

    fun info(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) = Unit
    fun info(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) = Unit

    fun notice(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) = Unit
    fun notice(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) = Unit

    fun warning(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) = Unit
    fun warning(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) = Unit

    fun error(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) = Unit
    fun error(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) = Unit

    fun critical(message: String, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) = Unit
    fun critical(category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap(), message: () -> String) = Unit

    fun error(throwable: Throwable, category: LogCategory = LogCategory.General, metadata: Map<String, String> = emptyMap()) = Unit

    fun logDecodingError(
        error: Throwable,
        url: String? = null,
        body: String? = null,
        typeName: String? = null,
        category: LogCategory = LogCategory.Decoding
    ) = Unit

    suspend fun importLogcatEntries(
        sinceMillis: Long = System.currentTimeMillis() - 3_600_000,
        category: LogCategory = LogCategory.Logcat
    ): Int = 0

    fun trackScreen(name: String, kind: String = "push") = Unit

    fun snapshot(): List<LogEntry> = emptyList()

    suspend fun snapshotAsync(): List<LogEntry> = emptyList()

    suspend fun loadPersistedEntries(): List<LogEntry> = emptyList()

    suspend fun loadPersistedPage(cursor: String? = null, minimumEntries: Int = 500): PersistedLogPage =
        PersistedLogPage()

    fun stream(): Flow<LogEntry> = emptyFlow()

    fun clear() = Unit

    suspend fun exportFile(): File? = null

    suspend fun exportFile(entries: List<LogEntry>): File? = null

    suspend fun exportNdjsonFile(entries: List<LogEntry>): File? = null
}

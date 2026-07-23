package com.olaf.internal

import android.content.Context
import com.olaf.LogCategory
import com.olaf.LogLevel
import com.olaf.OlafConfiguration
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * The state owner behind the `Olaf` facade: guards the store's lifecycle, the kill switch and the
 * level threshold. All mutable state sits behind [lock].
 */
internal class OlafRuntime {

    private val lock = ReentrantLock()
    private var store: LogStore? = null
    private var minimum: LogLevel = LogLevel.DEBUG
    private var enabled = true
    private var sessionId = ""
    private var cacheDirectory: File? = null
    private var notifier: OlafNotifier? = null

    /**
     * Logs emitted BEFORE `start()` are buffered here and flushed on start, so early launch
     * logging (splash, DI setup) isn't lost.
     */
    private val pending = ArrayDeque<PendingLog>()

    private class PendingLog(
        val date: Instant,
        val level: LogLevel,
        val category: LogCategory,
        val message: String,
        val metadata: Map<String, String>,
        val file: String,
        val line: Int,
        val function: String,
        val thread: String
    )

    /** Where a log call should go. */
    internal sealed interface LogTarget {
        /** Started and above the threshold → write straight through. */
        class Store(val store: LogStore) : LogTarget

        /** Not started yet → buffer, flushed on start. */
        data object Buffer : LogTarget

        /** Disabled or below the threshold → discard without computing the message. */
        data object Drop : LogTarget
    }

    // MARK: - Lifecycle

    /** Idempotent start — the first call wins. */
    fun start(context: Context, configuration: OlafConfiguration) {
        val appContext = context.applicationContext
        // The notifier needs a Context, so it is built here and handed to the store; the
        // Context-free `start` below stays usable from tests.
        notifier = if (configuration.showsNotification) {
            runCatching { OlafNotifier(appContext) }.getOrNull()
        } else {
            null
        }
        start(appContext.cacheDir, configuration)
    }

    /**
     * The Context-free half of [start] — everything Olaf needs from the app is its cache
     * directory, which also keeps the engine unit-testable without an Android runtime.
     */
    fun start(cacheDir: File, configuration: OlafConfiguration) {
        lock.withLock {
            if (store != null) return

            sessionId = makeSessionId()
            cacheDirectory = cacheDir

            val persistence = if (configuration.persistsToDisk) {
                FilePersistence.create(
                    directory = File(cacheDir, LOG_DIRECTORY_NAME),
                    maxFileSize = configuration.effectiveMaxFileSize,
                    maxFileCount = configuration.effectiveMaxFileCount,
                    retentionMillis = configuration.retentionMillis
                )
            } else {
                null
            }

            val mirror = if (configuration.mirrorsToLogcat) LogcatMirror(configuration.logcatTag) else null

            val created = LogStore(
                capacity = configuration.inMemoryCapacity,
                persistence = persistence,
                exportFormatter = configuration.exportFormatter,
                logcatMirror = mirror,
                notifier = notifier,
                sessionId = sessionId,
                cacheDirectory = cacheDir
            )
            store = created
            minimum = configuration.minimumLevel

            // Flush what was buffered before start, honouring the threshold.
            while (pending.isNotEmpty()) {
                val log = pending.removeFirst()
                if (log.level >= minimum) {
                    created.ingest(
                        date = log.date,
                        level = log.level,
                        category = log.category,
                        message = log.message,
                        metadata = log.metadata,
                        file = log.file,
                        line = log.line,
                        function = log.function,
                        thread = log.thread
                    )
                }
            }
        }
    }

    // MARK: - Access

    fun store(): LogStore? = lock.withLock { store }

    fun cacheDirectory(): File? = lock.withLock { cacheDirectory }

    /** Clears the capture notification — the viewer calls this once it is on screen. */
    fun dismissNotification() {
        lock.withLock { notifier }?.dismiss()
    }

    val isStarted: Boolean get() = lock.withLock { store != null }

    /** Current session identifier — populated by [start], empty before that. */
    val currentSessionId: String get() = lock.withLock { sessionId }

    var isEnabled: Boolean
        get() = lock.withLock { enabled }
        set(value) = lock.withLock { enabled = value }

    /**
     * Collection threshold. Seeded from the start configuration and changeable at runtime (the
     * viewer exposes it). Not persisted — scoped to the process lifetime.
     */
    var minimumLevel: LogLevel
        get() = lock.withLock { minimum }
        set(value) = lock.withLock { minimum = value }

    /** Decides where a log call goes; the message is only computed when this isn't [LogTarget.Drop]. */
    fun target(level: LogLevel): LogTarget = lock.withLock {
        if (!enabled) return LogTarget.Drop
        val current = store ?: return LogTarget.Buffer
        if (level >= minimum) LogTarget.Store(current) else LogTarget.Drop
    }

    /** Buffers a pre-start log (writes straight through if start happened in the meantime). */
    fun buffer(
        date: Instant,
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: Map<String, String>,
        file: String,
        line: Int,
        function: String,
        thread: String
    ) {
        lock.withLock {
            val current = store
            if (current != null) {
                current.ingest(date, level, category, message, metadata, file, line, function, thread)
                return
            }
            pending.addLast(
                PendingLog(date, level, category, message, metadata, file, line, function, thread)
            )
            while (pending.size > MAX_PENDING) {
                pending.removeFirst()
            }
        }
    }

    private companion object {
        const val MAX_PENDING = 1000
        const val LOG_DIRECTORY_NAME = "olaf"

        /** Sortable timestamp prefix plus a short random suffix. */
        fun makeSessionId(): String =
            "${System.currentTimeMillis()}-${UUID.randomUUID().toString().take(8)}"
    }
}

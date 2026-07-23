package com.olaf.internal

import com.olaf.LogCategory
import com.olaf.LogEntry
import com.olaf.LogFormatter
import com.olaf.LogLevel
import com.olaf.PersistedLogPage
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import java.util.concurrent.Callable
import java.util.concurrent.Executors

/**
 * Olaf's core store: in-memory ring buffer → (optionally) disk → live broadcast.
 *
 * Every mutation happens on a single writer thread, which makes entry ordering deterministic and
 * removes the need for locks around the buffer.
 */
internal class LogStore(
    private val capacity: Int,
    private val persistence: FilePersistence?,
    private val exportFormatter: LogFormatter,
    private val logcatMirror: LogcatMirror?,
    private val sessionId: String,
    private val cacheDirectory: File
) {

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "olaf-store").apply { isDaemon = true }
    }
    private val dispatcher = executor.asCoroutineDispatcher()

    /**
     * Fixed-capacity ring buffer holding the newest [capacity] entries. Append and evict are both
     * O(1) — a plain list with `removeAt(0)` would be O(n) on every write once full.
     */
    private val ring = arrayOfNulls<LogEntry>(capacity)
    private var size = 0
    private var head = 0

    /**
     * Live broadcast to the viewer. Bounded and drop-oldest, so a slow or paused collector can
     * never grow memory without bound — the buffer already holds the newest entries anyway.
     */
    private val _stream = MutableSharedFlow<LogEntry>(
        replay = 0,
        extraBufferCapacity = capacity,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val stream: SharedFlow<LogEntry> = _stream.asSharedFlow()

    // MARK: - Writing

    fun ingest(
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
        execute {
            val entry = LogEntry(
                date = date,
                level = level,
                category = category,
                message = message,
                metadata = metadata,
                file = file,
                line = line,
                function = function,
                thread = thread,
                sessionId = sessionId
            )

            ring[(head + size) % capacity] = entry
            if (size < capacity) {
                size++
            } else {
                head = (head + 1) % capacity // overwrite the oldest entry
            }

            persistence?.write(entry)
            logcatMirror?.log(entry)
            _stream.tryEmit(entry)
        }
    }

    // MARK: - Reading

    /** An instant copy of the buffer's entries, oldest to newest. */
    fun snapshot(): List<LogEntry> = try {
        executor.submit(Callable { orderedBuffer() }).get()
    } catch (_: Throwable) {
        emptyList()
    }

    /**
     * Non-blocking counterpart of [snapshot], so the caller (typically the main thread) never
     * waits on the writer thread while it is working through a burst of writes.
     */
    suspend fun snapshotAsync(): List<LogEntry> = withContext(dispatcher) { orderedBuffer() }

    /** Every entry on disk, including previous sessions. */
    suspend fun loadPersisted(): List<LogEntry> =
        withContext(dispatcher) { persistence?.loadEntries().orEmpty() }

    /** One page of on-disk history — see [FilePersistence.loadEntriesPage]. */
    suspend fun loadPersistedPage(cursor: String?, minimumEntries: Int): PersistedLogPage =
        withContext(dispatcher) {
            persistence?.loadEntriesPage(cursor, minimumEntries)
                ?: PersistedLogPage(emptyList(), null)
        }

    // MARK: - Management

    fun clear() {
        execute {
            ring.fill(null)
            size = 0
            head = 0
            persistence?.clear()
        }
    }

    // MARK: - Export

    /** Merges all on-disk entries into a shareable `.log` file. */
    suspend fun exportFile(): File? = withContext(dispatcher) {
        persistence?.consolidatedTextFile(cacheDirectory, exportFormatter)
    }

    /**
     * Writes the given entries — e.g. the viewer's currently **filtered** list — to a shareable
     * `.log` file. Independent of disk persistence: only what is passed in is exported.
     */
    suspend fun exportFile(entries: List<LogEntry>): File? = withContext(dispatcher) {
        val text = entries.joinToString("\n") { exportFormatter.format(it) }
        LogExportFile.write(cacheDirectory, text)
    }

    /**
     * Writes the given entries as **raw NDJSON** — the same schema as the on-disk format, so the
     * result can be piped losslessly into `jq` or any log tooling.
     */
    suspend fun exportNdjsonFile(entries: List<LogEntry>): File? = withContext(dispatcher) {
        val text = entries.joinToString("\n") { LogEntryCodec.encode(it) }
        LogExportFile.write(cacheDirectory, text, fileExtension = "ndjson")
    }

    // MARK: - Internal

    /** Called on the writer thread. */
    private fun orderedBuffer(): List<LogEntry> {
        val result = ArrayList<LogEntry>(size)
        for (offset in 0 until size) {
            ring[(head + offset) % capacity]?.let(result::add)
        }
        return result
    }

    private fun execute(block: () -> Unit) {
        try {
            executor.execute(block)
        } catch (_: Throwable) {
            // The executor only rejects once shut down; logging must not throw at that point.
        }
    }

}

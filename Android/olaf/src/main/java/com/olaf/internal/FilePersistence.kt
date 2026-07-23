package com.olaf.internal

import com.olaf.LogEntry
import com.olaf.LogFormatter
import com.olaf.PersistedLogPage
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

/**
 * Writes logs to disk as **NDJSON** (one JSON [LogEntry] per line), with size-based rotation and
 * file-count retention. NDJSON means entries read back with full fidelity, which is what makes
 * cross-session history possible; export converts to human-readable text separately.
 *
 * Not thread-safe on its own — it is only ever called from [LogStore]'s single writer thread.
 *
 * On-disk protection is left to the platform: app-internal storage is covered by file-based
 * encryption, which is the Android equivalent of the iOS build's file-protection attribute.
 */
internal class FilePersistence private constructor(
    private val directory: File,
    private val maxFileSize: Int,
    private val maxFileCount: Int,
    private val retentionMillis: Long,
    private val clock: () -> Long
) {

    private var stream: OutputStream? = null
    private var currentSize: Long = 0

    /**
     * Monotonic counter that keeps rotated file names unique when several rotations land in the
     * same second — a collision would silently drop a whole file's worth of logs.
     */
    private var rotationCounter = 0

    private val activeFile: File get() = File(directory, ACTIVE_FILE_NAME)

    // MARK: - Writing

    fun write(entry: LogEntry) {
        val stream = stream ?: return
        try {
            val line = (LogEntryCodec.encode(entry) + "\n").toByteArray()
            stream.write(line)
            stream.flush()
            currentSize += line.size
            if (currentSize >= maxFileSize) {
                rotate()
            }
        } catch (_: Throwable) {
            // A disk error must never break logging; fail silently.
        }
    }

    // MARK: - Reading (cross-session history)

    /** Parses every entry on disk, oldest to newest. Corrupt lines are skipped. */
    fun loadEntries(): List<LogEntry> =
        (rotatedFilesSortedAscending() + activeFile).flatMap(::decodeFile)

    /**
     * Reads on-disk history **paginated**, from the newest file backwards. The page unit is a
     * file: whole files are consumed until [minimumEntries] is reached (or files run out), so a
     * file is never split — and since files are capped at [maxFileSize], page size stays bounded.
     *
     * The cursor names the file the NEXT page starts at, fixed at the time this page is produced.
     * That way a rotation between two pages can't duplicate entries: newly rotated files are
     * newer than the cursor and therefore out of scope. If the cursor's file has since been
     * pruned, we fall back to the lexicographically closest older file (names carry a fixed-width
     * timestamp, so lexicographic order is chronological).
     */
    fun loadEntriesPage(cursorFileName: String?, minimumEntries: Int): PersistedLogPage {
        // Newest to oldest: the active file, then rotated files in reverse.
        val files = listOf(activeFile) + rotatedFilesSortedAscending().reversed()

        val startIndex = when {
            cursorFileName == null -> 0
            else -> {
                val exact = files.indexOfFirst { it.name == cursorFileName }
                if (exact >= 0) {
                    exact
                } else {
                    files.indexOfFirst { it.name != ACTIVE_FILE_NAME && it.name < cursorFileName }
                        .takeIf { it >= 0 } ?: files.size
                }
            }
        }

        val consumed = mutableListOf<List<LogEntry>>()
        var total = 0
        var index = startIndex
        while (index < files.size && total < maxOf(1, minimumEntries)) {
            val decoded = decodeFile(files[index])
            consumed.add(decoded)
            total += decoded.size
            index++
        }

        return PersistedLogPage(
            // Files were consumed newest to oldest; page content is returned oldest to newest.
            entries = consumed.asReversed().flatten(),
            nextCursor = files.getOrNull(index)?.name
        )
    }

    private fun decodeFile(file: File): List<LogEntry> {
        if (!file.exists()) return emptyList()
        return try {
            file.useLines { lines ->
                lines.mapNotNull { line ->
                    if (line.isBlank()) null else LogEntryCodec.decode(line)
                }.toList()
            }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    // MARK: - Clearing & export

    fun clear() {
        closeQuietly()
        allLogFiles().forEach { it.delete() }
        openActiveFile()
    }

    /** Renders every entry on disk through [formatter] and writes a shareable text file. */
    fun consolidatedTextFile(cacheDirectory: File, formatter: LogFormatter): File? {
        val text = loadEntries().joinToString("\n") { formatter.format(it) }
        return LogExportFile.write(cacheDirectory, text)
    }

    // MARK: - Internal

    private fun openActiveFile() {
        val file = activeFile
        if (!file.exists()) file.createNewFile()
        stream = BufferedOutputStream(FileOutputStream(file, /* append = */ true))
        currentSize = file.length()
    }

    private fun rotate() {
        closeQuietly()

        rotationCounter++
        val stamp = System.currentTimeMillis() / 1000
        // Fixed-width seconds + a monotonic counter → same-second rotations never collide.
        var rotated = File(directory, String.format(ROTATED_NAME_FORMAT, stamp, rotationCounter))
        if (rotated.exists()) {
            // Covers a process restart that rotates within the same second (counter reset).
            rotated = File(directory, "$ROTATED_PREFIX$stamp-${System.nanoTime()}.$FILE_EXTENSION")
        }
        activeFile.renameTo(rotated)

        currentSize = 0
        openActiveFile()
        pruneOldFiles()
    }

    /**
     * Enforces both retention limits on rotated files (the active file is never pruned):
     * anything older than [retentionMillis], and anything beyond [maxFileCount].
     *
     * Both are needed. The count alone lets a quiet week keep month-old logs around; the age alone
     * lets a busy hour fill the disk. Whichever limit bites first wins.
     */
    private fun pruneOldFiles() {
        var rotated = rotatedFilesSortedAscending()

        if (retentionMillis > 0) {
            val cutoff = clock() - retentionMillis
            val (expired, kept) = rotated.partition { it.lastModified() < cutoff }
            expired.forEach { it.delete() }
            rotated = kept
        }

        val allowedRotated = maxOf(0, maxFileCount - 1)
        if (rotated.size <= allowedRotated) return
        rotated.take(rotated.size - allowedRotated).forEach { it.delete() }
    }

    private fun allLogFiles(): List<File> = rotatedFilesSortedAscending() + activeFile

    private fun rotatedFilesSortedAscending(): List<File> =
        (directory.listFiles() ?: emptyArray())
            .filter {
                it.name.startsWith(ROTATED_PREFIX) &&
                    it.name != ACTIVE_FILE_NAME &&
                    it.extension == FILE_EXTENSION
            }
            // Rotated files are never written again, so last-modified is the rotation time;
            // the name breaks ties (and is itself chronological).
            .sortedWith(compareBy({ it.lastModified() }, { it.name }))

    private fun closeQuietly() {
        try {
            stream?.flush()
            stream?.close()
        } catch (_: Throwable) {
            // Ignored — we are tearing the handle down anyway.
        }
        stream = null
    }

    companion object {
        private const val ACTIVE_FILE_NAME = "olaf-current.ndjson"
        private const val ROTATED_PREFIX = "olaf-"
        private const val FILE_EXTENSION = "ndjson"
        private const val ROTATED_NAME_FORMAT = "$ROTATED_PREFIX%010d-%06d.$FILE_EXTENSION"

        /** Returns `null` when the directory can't be prepared — persistence is then skipped. */
        fun create(
            directory: File,
            maxFileSize: Int,
            maxFileCount: Int,
            retentionMillis: Long = 0,
            clock: () -> Long = System::currentTimeMillis
        ): FilePersistence? = try {
            directory.mkdirs()
            FilePersistence(directory, maxFileSize, maxFileCount, retentionMillis, clock).apply {
                openActiveFile()
                pruneOldFiles()
            }
        } catch (_: Throwable) {
            null
        }
    }
}

package com.olaf

import com.olaf.internal.FilePersistence
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.Instant

/** History pagination — reading newest to oldest with a file-bounded cursor. */
class HistoryPaginationTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val logDirectory: File get() = File(temporaryFolder.root, "logs")

    private fun makeEntry(message: String) = LogEntry(
        date = Instant.now(),
        level = LogLevel.INFO,
        category = LogCategory.General,
        message = message,
        metadata = emptyMap(),
        file = "T.kt",
        line = 1,
        function = "f()",
        thread = "main"
    )

    /** Builds a multi-file history by rotating on a small max file size. */
    private fun makeRotatedHistory(entryCount: Int, perFileBytes: Int = 2000): FilePersistence {
        val persistence = requireNotNull(
            FilePersistence.create(logDirectory, maxFileSize = perFileBytes, maxFileCount = 100)
        )
        (1..entryCount).forEach {
            persistence.write(makeEntry("x".repeat(600) + "#$it"))
        }
        return persistence
    }

    @Test
    fun `first page returns the newest entries`() {
        val persistence = makeRotatedHistory(entryCount = 12)

        val page = persistence.loadEntriesPage(cursorFileName = null, minimumEntries = 3)
        assertFalse(page.entries.isEmpty())
        assertNotNull(page.nextCursor) // the rest is still there
        assertTrue(page.entries.any { it.message.endsWith("#12") })

        // Within a page, entries run oldest to newest.
        val numbers = page.entries.mapNotNull { it.message.substringAfterLast('#').toIntOrNull() }
        assertEquals(numbers.sorted(), numbers)
    }

    @Test
    fun `cursor walk covers all entries exactly once`() {
        val persistence = makeRotatedHistory(entryCount = 20)
        val all = persistence.loadEntries()

        val collected = mutableListOf<LogEntry>()
        var cursor: String? = null
        var pages = 0
        do {
            val page = persistence.loadEntriesPage(cursor, minimumEntries = 4)
            collected.addAll(0, page.entries) // prepend, the way the viewer does
            cursor = page.nextCursor
            pages++
            assertTrue("cursor is not advancing (infinite loop)", pages < 100)
        } while (cursor != null)

        assertTrue("expected multi-file pagination", pages > 1)
        assertEquals(all.map { it.id }, collected.map { it.id })
    }

    @Test
    fun `minimumEntries spans multiple files`() {
        val persistence = makeRotatedHistory(entryCount = 12)
        // One file holds ~2-3 entries, so asking for 8 has to consume several files.
        val page = persistence.loadEntriesPage(cursorFileName = null, minimumEntries = 8)
        assertTrue(page.entries.size >= 8)
    }

    @Test
    fun `a deleted cursor file falls back to older files`() {
        val persistence = makeRotatedHistory(entryCount = 12)
        val first = persistence.loadEntriesPage(cursorFileName = null, minimumEntries = 3)
        val cursor = requireNotNull(first.nextCursor)

        // Simulate the cursor's file having been pruned between two pages.
        File(logDirectory, cursor).delete()

        val second = persistence.loadEntriesPage(cursor, minimumEntries = 3)
        val firstIds = first.entries.map { it.id }.toSet()
        assertFalse(second.entries.isEmpty())
        assertTrue(second.entries.none { it.id in firstIds })
    }

    @Test
    fun `an empty store returns an empty page without a cursor`() {
        val persistence = requireNotNull(FilePersistence.create(logDirectory, 1_048_576, 5))
        val page = persistence.loadEntriesPage(cursorFileName = null, minimumEntries = 100)
        assertTrue(page.entries.isEmpty())
        assertNull(page.nextCursor)
    }
}

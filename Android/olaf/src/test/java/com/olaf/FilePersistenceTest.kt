package com.olaf

import com.olaf.internal.FilePersistence
import com.olaf.internal.LogEntryCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.Instant

class FilePersistenceTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val logDirectory: File get() = File(temporaryFolder.root, "logs")

    private fun makePersistence(maxFileSize: Int = 1_048_576, maxFileCount: Int = 5) =
        requireNotNull(FilePersistence.create(logDirectory, maxFileSize, maxFileCount))

    private fun makeEntry(message: String, level: LogLevel = LogLevel.INFO) = LogEntry(
        date = Instant.now(),
        level = level,
        category = LogCategory.General,
        message = message,
        metadata = mapOf("k" to "v"),
        file = "Test.kt",
        line = 1,
        function = "f()",
        thread = "main"
    )

    @Test
    fun `write then load round-trips`() {
        val persistence = makePersistence()
        persistence.write(makeEntry("first"))
        persistence.write(makeEntry("second"))

        val loaded = persistence.loadEntries()
        assertEquals(listOf("first", "second"), loaded.map { it.message })
        assertEquals("v", loaded.first().metadata["k"])
    }

    @Test
    fun `entries persist across instances`() {
        makePersistence().write(makeEntry("session-1"))

        // A new instance is a new "session"; the previous entry must still be on disk.
        val second = makePersistence()
        second.write(makeEntry("session-2"))

        assertEquals(listOf("session-1", "session-2"), second.loadEntries().map { it.message })
    }

    @Test
    fun `rotation keeps recent files and prunes old ones`() {
        // Small max size → rotates on every write; maxFileCount = 3 → older files are deleted.
        val persistence = makePersistence(maxFileSize = 4096, maxFileCount = 3)
        (1..10).forEach {
            persistence.write(makeEntry("x".repeat(5000) + "#$it"))
        }

        val files = logDirectory.listFiles()?.filter { it.name.endsWith(".ndjson") }.orEmpty()
        // active + at most (maxFileCount - 1) rotated
        assertTrue("expected at most 3 files, got ${files.size}", files.size <= 3)
        assertTrue(persistence.loadEntries().any { it.message.contains("#10") })
    }

    @Test
    fun `consolidated text file is plain text, not json`() {
        val persistence = makePersistence()
        persistence.write(makeEntry("readable line", level = LogLevel.ERROR))

        val file = persistence.consolidatedTextFile(temporaryFolder.root, PlainTextFormatter())
        assertNotNull(file)
        val text = file!!.readText()
        assertTrue(text.contains("[ERROR]"))
        assertTrue(text.contains("readable line"))
        assertFalse(text.contains("\"message\""))
    }

    @Test
    fun `clear removes all entries`() {
        val persistence = makePersistence()
        persistence.write(makeEntry("to be cleared"))
        persistence.clear()
        assertTrue(persistence.loadEntries().isEmpty())
    }

    @Test
    fun `codec round-trips an entry`() {
        val entry = makeEntry("codable", level = LogLevel.WARNING)
        val decoded = requireNotNull(LogEntryCodec.decode(LogEntryCodec.encode(entry)))

        assertEquals("codable", decoded.message)
        assertEquals(LogLevel.WARNING, decoded.level)
        assertEquals(LogCategory.General, decoded.category)
        assertEquals("v", decoded.metadata["k"])
        assertEquals(entry.id, decoded.id)
    }

    @Test
    fun `codec reads the second-precision timestamps written by the iOS package`() {
        val line = """{"id":"abc","date":"2026-07-23T10:00:00Z","level":5,"category":"network",""" +
            """"message":"from iOS","metadata":{},"file":"F.swift","line":9,"function":"f()",""" +
            """"thread":"main","sessionID":"s1"}"""

        val decoded = requireNotNull(LogEntryCodec.decode(line))
        assertEquals("from iOS", decoded.message)
        assertEquals(LogLevel.ERROR, decoded.level)
        assertEquals(Instant.parse("2026-07-23T10:00:00Z"), decoded.date)
    }

    @Test
    fun `corrupt lines are skipped instead of breaking history`() {
        val persistence = makePersistence()
        persistence.write(makeEntry("good-1"))
        File(logDirectory, "olaf-current.ndjson").appendText("{not json at all\n")
        persistence.write(makeEntry("good-2"))

        assertEquals(listOf("good-1", "good-2"), persistence.loadEntries().map { it.message })
    }
}

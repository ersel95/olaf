package com.olaf.ui

import com.olaf.LogCategory
import com.olaf.LogEntry
import com.olaf.LogLevel
import com.olaf.ui.model.LogViewerModel
import com.olaf.ui.model.NetworkContentKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** The viewer's derivation logic: filtering, session grouping and the default chip selection. */
class LogViewerModelTest {

    private fun entry(
        message: String = "hello",
        level: LogLevel = LogLevel.INFO,
        category: LogCategory = LogCategory.General,
        metadata: Map<String, String> = emptyMap(),
        sessionId: String = "s1",
        secondsFromEpoch: Long = 0
    ) = LogEntry(
        date = Instant.ofEpochSecond(secondsFromEpoch),
        level = level,
        category = category,
        message = message,
        metadata = metadata,
        sessionId = sessionId
    )

    private val allLevels = LogLevel.entries.toSet()

    @Test
    fun `filter returns newest first`() {
        val entries = listOf(entry("first"), entry("second"), entry("third"))
        val filtered = LogViewerModel.filter(entries, "", allLevels, emptySet())
        assertEquals(listOf("third", "second", "first"), filtered.map { it.message })
    }

    @Test
    fun `level filter hides other levels`() {
        val entries = listOf(entry("a", level = LogLevel.DEBUG), entry("b", level = LogLevel.ERROR))
        val filtered = LogViewerModel.filter(entries, "", setOf(LogLevel.ERROR), emptySet())
        assertEquals(listOf("b"), filtered.map { it.message })
    }

    @Test
    fun `category filter hides other categories`() {
        val entries = listOf(
            entry("a", category = LogCategory.Auth),
            entry("b", category = LogCategory.Network, metadata = mapOf("url" to "https://x"))
        )
        val filtered = LogViewerModel.filter(entries, "", allLevels, setOf(LogCategory.Network))
        assertEquals(listOf("b"), filtered.map { it.message })
    }

    @Test
    fun `search matches message, category and metadata`() {
        val entries = listOf(
            entry("Login succeeded", category = LogCategory.Auth),
            entry("Transfer", metadata = mapOf("iban" to "NL91ABNA0417164300")),
            entry("Unrelated")
        )

        assertEquals(1, LogViewerModel.filter(entries, "login", allLevels, emptySet()).size)
        assertEquals(1, LogViewerModel.filter(entries, "auth", allLevels, emptySet()).size)
        assertEquals(1, LogViewerModel.filter(entries, "nl91abna", allLevels, emptySet()).size)
        assertEquals(3, LogViewerModel.filter(entries, "", allLevels, emptySet()).size)
    }

    @Test
    fun `content kind filter hides non-network entries`() {
        val entries = listOf(
            entry("plain log"),
            entry(
                "network",
                category = LogCategory.Network,
                metadata = mapOf("url" to "https://x", "respH.Content-Type" to "application/json")
            )
        )
        val filtered = LogViewerModel.filter(
            entries, "", allLevels, emptySet(), setOf(NetworkContentKind.JSON)
        )
        assertEquals(listOf("network"), filtered.map { it.message })
    }

    @Test
    fun `sessions are grouped newest first, excluding the current one`() {
        val entries = listOf(
            entry("old", sessionId = "s1", secondsFromEpoch = 10),
            entry("older", sessionId = "s1", secondsFromEpoch = 20),
            entry("newer", sessionId = "s2", secondsFromEpoch = 100),
            entry("current", sessionId = "now", secondsFromEpoch = 200)
        )

        val sessions = LogViewerModel.groupSessions(entries, current = "now")
        assertEquals(listOf("s2", "s1"), sessions.map { it.id })
        assertEquals(Instant.ofEpochSecond(10), sessions.last().startedAt)
        assertTrue(sessions.none { it.id == "now" })
    }

    @Test
    fun `network is preselected only when network entries exist`() {
        assertEquals(emptySet<LogCategory>(), LogViewerModel.defaultCategorySelection(listOf(entry("a"))))
        assertEquals(
            setOf(LogCategory.Network),
            LogViewerModel.defaultCategorySelection(
                listOf(entry("a"), entry("b", category = LogCategory.Network))
            )
        )
    }

    @Test
    fun `available categories are deduplicated and sorted`() {
        val entries = listOf(
            entry(category = LogCategory.Network),
            entry(category = LogCategory.Auth),
            entry(category = LogCategory.Network)
        )
        assertEquals(
            listOf(LogCategory.Auth, LogCategory.Network),
            LogViewerModel.categoriesIn(entries)
        )
    }
}

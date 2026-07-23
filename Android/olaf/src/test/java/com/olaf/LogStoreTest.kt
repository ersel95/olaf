package com.olaf

import com.olaf.internal.LogStore
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.Instant

class LogStoreTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private fun makeStore(capacity: Int) = LogStore(
        capacity = capacity,
        persistence = null,
        exportFormatter = PlainTextFormatter(),
        logcatMirror = null,
        notifier = null,
        sessionId = "test-session",
        cacheDirectory = temporaryFolder.root
    )

    private fun LogStore.ingest(message: String, level: LogLevel = LogLevel.INFO) {
        ingest(
            date = Instant.now(),
            level = level,
            category = LogCategory.General,
            message = message,
            metadata = emptyMap(),
            file = "Test.kt",
            line = 1,
            function = "test()",
            thread = "main"
        )
    }

    @Test
    fun `stores and returns snapshot`() {
        val store = makeStore(capacity = 10)
        store.ingest("a")
        store.ingest("b")
        assertEquals(listOf("a", "b"), store.snapshot().map { it.message })
    }

    @Test
    fun `ring buffer evicts oldest beyond capacity`() {
        val store = makeStore(capacity = 3)
        (1..5).forEach { store.ingest("$it") }
        val snapshot = store.snapshot()
        assertEquals(3, snapshot.size)
        assertEquals(listOf("3", "4", "5"), snapshot.map { it.message })
    }

    @Test
    fun `ring buffer multiple wraps preserve order`() {
        val store = makeStore(capacity = 3)
        (1..8).forEach { store.ingest("$it") }
        assertEquals(listOf("6", "7", "8"), store.snapshot().map { it.message })
    }

    @Test
    fun `snapshotAsync matches snapshot`() = runTest {
        val store = makeStore(capacity = 5)
        (1..3).forEach { store.ingest("$it") }
        assertEquals(listOf("1", "2", "3"), store.snapshotAsync().map { it.message })
    }

    @Test
    fun `raw data is stored unchanged`() {
        // No masking or filtering: even sensitive-looking data is kept exactly as-is.
        val store = makeStore(capacity = 10)
        store.ingest("PAN=4508034012345678")
        assertEquals("PAN=4508034012345678", store.snapshot().first().message)
    }

    @Test
    fun `clear empties the buffer`() {
        val store = makeStore(capacity = 10)
        store.ingest("a")
        store.clear()
        // clear is queued on the writer thread; snapshot queues behind it, so it has completed.
        assertTrue(store.snapshot().isEmpty())
    }

    @Test
    fun `export writes only the given entries`() = runTest {
        // Filtered export: the viewer passes the visible subset, and only that is written.
        val store = makeStore(capacity = 10)
        (1..5).forEach { store.ingest("msg-$it") }
        val subset = store.snapshot().take(2)

        val exported = store.exportFile(subset)
        assertNotNull(exported)
        val text = exported!!.readText()

        assertTrue(text.contains("msg-1"))
        assertTrue(text.contains("msg-2"))
        assertFalse(text.contains("msg-3"))
        assertFalse(text.contains("msg-5"))
    }

    @Test
    fun `ndjson export round-trips through the codec`() = runTest {
        val store = makeStore(capacity = 10)
        store.ingest("ndjson-line")
        val exported = store.exportNdjsonFile(store.snapshot())
        assertNotNull(exported)
        val lines = exported!!.readLines().filter { it.isNotBlank() }
        assertEquals(1, lines.size)
        assertTrue(lines.first().contains("\"message\""))
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun `stream receives new entries`() = runTest {
        val store = makeStore(capacity = 10)
        val received = async { store.stream.first().message }
        // Let the collector subscribe before the entry is emitted.
        yield()
        Thread.sleep(50)
        store.ingest("live")
        assertEquals("live", received.await())
    }
}

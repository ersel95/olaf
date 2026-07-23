package com.olaf

import com.olaf.internal.OlafRuntime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.Instant

/** Logs emitted before `start()` must survive and be flushed once the store exists. */
class PreStartBufferTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private fun OlafRuntime.buffer(message: String, level: LogLevel = LogLevel.INFO) {
        buffer(
            date = Instant.now(),
            level = level,
            category = LogCategory.General,
            message = message,
            metadata = emptyMap(),
            file = "F.kt",
            line = 1,
            function = "f()",
            thread = "main"
        )
    }

    private fun OlafRuntime.startForTest(minimumLevel: LogLevel = LogLevel.TRACE) {
        start(
            cacheDir = temporaryFolder.root,
            configuration = OlafConfiguration(
                minimumLevel = minimumLevel,
                persistsToDisk = false,
                mirrorsToLogcat = false
            )
        )
    }

    private fun OlafRuntime.storedMessages(level: LogLevel = LogLevel.INFO): List<String> {
        val target = target(level)
        assertTrue("expected a store target, got $target", target is OlafRuntime.LogTarget.Store)
        return (target as OlafRuntime.LogTarget.Store).store.snapshot().map { it.message }
    }

    @Test
    fun `target is buffer before start`() {
        val runtime = OlafRuntime()
        assertTrue(runtime.target(LogLevel.INFO) is OlafRuntime.LogTarget.Buffer)
    }

    @Test
    fun `pre-start logs are flushed on start`() {
        val runtime = OlafRuntime()
        runtime.buffer("early-1")
        runtime.buffer("early-2")

        runtime.startForTest()

        assertEquals(listOf("early-1", "early-2"), runtime.storedMessages())
    }

    @Test
    fun `flush respects the minimum level`() {
        val runtime = OlafRuntime()
        runtime.buffer("low", level = LogLevel.DEBUG)
        runtime.buffer("high", level = LogLevel.ERROR)

        runtime.startForTest(minimumLevel = LogLevel.WARNING)

        assertEquals(listOf("high"), runtime.storedMessages(LogLevel.ERROR))
    }

    @Test
    fun `buffering after start goes straight to the store`() {
        val runtime = OlafRuntime()
        runtime.startForTest()
        runtime.buffer("after-start")

        assertEquals(listOf("after-start"), runtime.storedMessages())
    }

    @Test
    fun `the kill switch drops everything`() {
        val runtime = OlafRuntime()
        runtime.startForTest()
        runtime.isEnabled = false

        assertTrue(runtime.target(LogLevel.CRITICAL) is OlafRuntime.LogTarget.Drop)
    }

    @Test
    fun `start is idempotent`() {
        val runtime = OlafRuntime()
        runtime.startForTest()
        val sessionId = runtime.currentSessionId
        runtime.startForTest()

        assertEquals(sessionId, runtime.currentSessionId)
    }
}

package com.olaf

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class FormatterTest {

    private fun makeEntry(
        level: LogLevel = LogLevel.INFO,
        category: LogCategory = LogCategory.Auth,
        message: String = "hello",
        metadata: Map<String, String> = mapOf("method" to "biometric")
    ) = LogEntry(
        date = Instant.EPOCH,
        level = level,
        category = category,
        message = message,
        metadata = metadata,
        file = "com/example/auth/LoginScreen.kt",
        line = 42,
        function = "login()",
        thread = "main"
    )

    @Test
    fun `plain text contains level, category and message`() {
        val line = PlainTextFormatter().format(makeEntry())
        assertTrue(line.contains("[INFO]"))
        assertTrue(line.contains("[auth]"))
        assertTrue(line.contains("hello"))
        assertTrue(line.contains("method=biometric"))
        assertTrue(line.contains("LoginScreen.kt:42"))
    }

    @Test
    fun `plain text can omit metadata and source`() {
        val line = PlainTextFormatter(includesMetadata = false, includesSource = false)
            .format(makeEntry())
        assertFalse(line.contains("method=biometric"))
        assertFalse(line.contains("LoginScreen.kt"))
    }

    @Test
    fun `json formatter produces valid json`() {
        val json = JSONObject(JsonLogFormatter().format(makeEntry()))
        assertEquals("hello", json.getString("message"))
        assertEquals(42, json.getInt("line"))
        assertEquals("auth", json.getString("category"))
        assertEquals(LogLevel.INFO.ordinal, json.getInt("level"))
    }

    @Test
    fun `file name strips the path`() {
        assertEquals("LoginScreen.kt", makeEntry().fileName)
    }
}

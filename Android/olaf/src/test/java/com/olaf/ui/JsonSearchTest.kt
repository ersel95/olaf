package com.olaf.ui

import com.olaf.internal.LogcatImportParser
import com.olaf.LogLevel
import com.olaf.ui.util.Formatting
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

/**
 * Searching inside a body keeps JSON blocks whole — a match that only shows `"accounts": [` tells
 * the reader nothing.
 */
class JsonSearchTest {

    private val json = """
        {
          "user": {
            "name": "Ada",
            "accounts": [
              {
                "iban": "NL91ABNA0417164300",
                "balance": 42
              }
            ]
          },
          "meta": {
            "page": 1
          }
        }
    """.trimIndent()

    @Test
    fun `a match that opens a block pulls in the whole block`() {
        val result = Formatting.searchKeepingJsonBlocks(json, "accounts")!!

        assertTrue(result.contains("\"accounts\": ["))
        // The block's contents came along, down to its closing bracket.
        assertTrue(result.contains("iban"))
        assertTrue(result.contains("balance"))
        assertTrue(result.contains("]"))
        // An unrelated sibling did not.
        assertFalse(result.contains("\"page\""))
    }

    @Test
    fun `a leaf match returns only its line`() {
        val result = Formatting.searchKeepingJsonBlocks(json, "NL91")!!
        assertTrue(result.contains("NL91ABNA0417164300"))
        assertFalse(result.contains("\"name\""))
    }

    @Test
    fun `disjoint results are separated by an ellipsis`() {
        val result = Formatting.searchKeepingJsonBlocks(json, "\"name\"")!!
        val second = Formatting.searchKeepingJsonBlocks(json, "page")!!
        assertFalse(result.contains("⋯")) // a single hit needs no separator

        val both = Formatting.searchKeepingJsonBlocks(json, "a")!!
        assertTrue("expected a gap marker between distant hits", both.contains("⋯"))
        assertTrue(second.contains("page"))
    }

    @Test
    fun `no match returns null`() {
        assertNull(Formatting.searchKeepingJsonBlocks(json, "nonexistent-token"))
    }

    @Test
    fun `brackets inside strings do not affect depth`() {
        val tricky = """
            {
              "label": "a [bracket] in a string {",
              "list": [
                1
              ]
            }
        """.trimIndent()

        val result = Formatting.searchKeepingJsonBlocks(tricky, "list")!!
        assertTrue(result.contains("\"list\": ["))
        assertTrue(result.contains("1"))
        assertTrue(result.trimEnd().endsWith("]"))
    }

    @Test
    fun `looksLikeJson tolerates truncated payloads`() {
        assertTrue(Formatting.looksLikeJson("""{"a": 1"""))   // truncated, still JSON-ish
        assertTrue(Formatting.looksLikeJson("""  [1, 2"""))
        assertFalse(Formatting.looksLikeJson("plain text"))
    }
}

/** Parsing Logcat's `threadtime` output back into entries. */
class LogcatImportParserTest {

    private val now: Instant = Instant.parse("2026-07-23T11:20:00Z")

    @Test
    fun `parses a threadtime line`() {
        val parsed = LogcatImportParser.parse(
            "07-23 11:15:35.078  8514  8537 I SomeTag: the message",
            now = now,
            zone = ZoneOffset.UTC
        )!!

        assertEquals(LogLevel.INFO, parsed.level)
        assertEquals("SomeTag", parsed.tag)
        assertEquals("the message", parsed.message)
        assertEquals(Instant.parse("2026-07-23T11:15:35.078Z"), parsed.timestamp)
    }

    @Test
    fun `maps every priority`() {
        fun levelOf(priority: String) = LogcatImportParser.parse(
            "07-23 11:15:35.078  1  1 $priority T: m", now, ZoneOffset.UTC
        )!!.level

        assertEquals(LogLevel.TRACE, levelOf("V"))
        assertEquals(LogLevel.DEBUG, levelOf("D"))
        assertEquals(LogLevel.INFO, levelOf("I"))
        assertEquals(LogLevel.WARNING, levelOf("W"))
        assertEquals(LogLevel.ERROR, levelOf("E"))
        assertEquals(LogLevel.CRITICAL, levelOf("F"))
    }

    @Test
    fun `a line stamped in the future is dated to the previous year`() {
        // Logcat omits the year; a December line read in January must not land in the future.
        val parsed = LogcatImportParser.parse(
            "12-31 23:59:00.000  1  1 I T: end of year",
            now = Instant.parse("2026-01-02T10:00:00Z"),
            zone = ZoneOffset.UTC
        )!!
        assertEquals(Instant.parse("2025-12-31T23:59:00Z"), parsed.timestamp)
    }

    @Test
    fun `non-matching lines are ignored`() {
        assertNull(LogcatImportParser.parse("--------- beginning of main", now, ZoneOffset.UTC))
        assertNull(LogcatImportParser.parse("", now, ZoneOffset.UTC))
    }
}

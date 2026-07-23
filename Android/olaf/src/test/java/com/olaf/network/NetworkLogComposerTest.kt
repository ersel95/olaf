package com.olaf.network

import com.olaf.LogLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Capture rules: level derivation, message shape and the metadata contract shared with iOS. */
class NetworkLogComposerTest {

    private fun cancelledEvent() = NetworkLogEvent(
        method = "GET",
        url = "https://api.example.com/feed",
        durationMs = 42,
        cancelled = true
    )

    @Test
    fun `level maps status codes and errors`() {
        assertEquals(LogLevel.INFO, NetworkLogComposer.level(200, null))
        assertEquals(LogLevel.INFO, NetworkLogComposer.level(304, null))
        assertEquals(LogLevel.WARNING, NetworkLogComposer.level(404, null))
        assertEquals(LogLevel.ERROR, NetworkLogComposer.level(500, null))
        assertEquals(LogLevel.ERROR, NetworkLogComposer.level(null, "timeout"))
        assertEquals(LogLevel.INFO, NetworkLogComposer.level(null, null))
    }

    @Test
    fun `a cancelled call is info, not an error`() {
        assertEquals(LogLevel.INFO, NetworkLogComposer.level(null, null, cancelled = true))
        // Cancellation wins over an error message.
        assertEquals(LogLevel.INFO, NetworkLogComposer.level(null, "cancelled", cancelled = true))
    }

    @Test
    fun `cancelled message and metadata`() {
        val event = cancelledEvent()
        assertTrue(NetworkLogComposer.message(event).contains("cancelled"))
        val metadata = NetworkLogComposer.metadata(event)
        assertEquals("true", metadata["cancelled"])
        assertNull(metadata["error"])
    }

    @Test
    fun `a non-cancelled event carries no cancelled key`() {
        val event = cancelledEvent().copy(cancelled = false)
        assertNull(NetworkLogComposer.metadata(event)["cancelled"])
        assertFalse(NetworkLogComposer.message(event).contains("cancelled"))
    }

    @Test
    fun `metadata keys match the iOS schema`() {
        val event = NetworkLogEvent(
            method = "POST",
            url = "https://api.example.com/v1/transfer",
            statusCode = 201,
            durationMs = 120,
            requestBytes = 34,
            responseBytes = 56,
            requestBody = "{}",
            responseBody = "{\"ok\":true}",
            requestHeaders = mapOf("Authorization" to "Bearer abc"),
            responseHeaders = mapOf("Content-Type" to "application/json"),
            timing = NetworkTimingMetrics(
                dnsMs = 5, connectMs = 12, tlsMs = 20, ttfbMs = 80,
                protocolName = "h2", reusedConnection = false
            )
        )

        val metadata = NetworkLogComposer.metadata(event)
        assertEquals("POST", metadata["method"])
        assertEquals("https://api.example.com/v1/transfer", metadata["url"])
        assertEquals("201", metadata["status"])
        assertEquals("120", metadata["durationMs"])
        assertEquals("34", metadata["reqBytes"])
        assertEquals("56", metadata["respBytes"])
        assertEquals("{}", metadata["requestBody"])
        // Headers are raw, one key per header, with the iOS prefixes.
        assertEquals("Bearer abc", metadata["reqH.Authorization"])
        assertEquals("application/json", metadata["respH.Content-Type"])
        // Timing lives under `t.`
        assertEquals("5", metadata["t.dnsMs"])
        assertEquals("12", metadata["t.connectMs"])
        assertEquals("20", metadata["t.tlsMs"])
        assertEquals("80", metadata["t.ttfbMs"])
        assertEquals("h2", metadata["t.protocol"])
        assertEquals("false", metadata["t.reused"])
    }

    @Test
    fun `sensitive headers are never redacted`() {
        // Olaf stores everything raw by design; masking is the host's responsibility.
        val event = NetworkLogEvent(
            method = "GET",
            url = "https://a.com",
            requestHeaders = mapOf("Authorization" to "Bearer secret-token")
        )
        assertEquals("Bearer secret-token", NetworkLogComposer.metadata(event)["reqH.Authorization"])
    }

    @Test
    fun `message includes the mock marker`() {
        val event = NetworkLogEvent(method = "GET", url = "https://a.com", statusCode = 200, mocked = true)
        val message = NetworkLogComposer.message(event)
        assertTrue(message.contains("[mock]"))
        assertEquals("true", NetworkLogComposer.metadata(event)["mocked"])
    }
}

/** The allow/deny URL filter that decides whether a call is captured at all. */
class CaptureFilterTest {

    @Test
    fun `an empty filter captures everything`() {
        val config = OlafNetworkConfiguration()
        assertTrue(config.shouldCapture("https://anything.com/x"))
    }

    @Test
    fun `exclusion wins over inclusion`() {
        val config = OlafNetworkConfiguration(
            includedUrls = listOf("example.com"),
            excludedUrls = listOf("example.com/health")
        )
        assertTrue(config.shouldCapture("https://api.example.com/v1"))
        assertFalse(config.shouldCapture("https://api.example.com/health"))
    }

    @Test
    fun `inclusion narrows capture to the listed hosts`() {
        val config = OlafNetworkConfiguration(includedUrls = listOf("api.example.com"))
        assertTrue(config.shouldCapture("https://api.example.com/x"))
        assertFalse(config.shouldCapture("https://other.com/x"))
    }

    @Test
    fun `filters are case-insensitive`() {
        val config = OlafNetworkConfiguration(excludedUrls = listOf("CrashLytics"))
        assertFalse(config.shouldCapture("https://api.crashlytics.com/x"))
    }
}

package com.olaf.ui

import com.olaf.LogCategory
import com.olaf.LogEntry
import com.olaf.LogLevel
import com.olaf.ui.model.NetworkContentKind
import com.olaf.ui.model.NetworkLogInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Parsing captured metadata back into the structured shape the viewer renders. */
class NetworkLogInfoTest {

    private fun networkEntry(metadata: Map<String, String>) = LogEntry(
        date = Instant.EPOCH,
        level = LogLevel.INFO,
        category = LogCategory.Network,
        message = "GET https://api.example.com/v1/accounts → 200",
        metadata = metadata
    )

    private val fullMetadata = mapOf(
        "method" to "GET",
        "url" to "https://api.example.com/v1/accounts?page=2",
        "status" to "200",
        "durationMs" to "120",
        "reqBytes" to "0",
        "respBytes" to "2048",
        "reqH.Authorization" to "Bearer abc",
        "respH.Content-Type" to "application/json",
        "t.dnsMs" to "5",
        "t.protocol" to "h2",
        "t.reused" to "false"
    )

    @Test
    fun `parses the captured metadata`() {
        val info = NetworkLogInfo.from(networkEntry(fullMetadata))!!

        assertEquals("GET", info.method)
        assertEquals(200, info.statusCode)
        assertEquals(120L, info.durationMs)
        assertEquals(2048L, info.responseBytes)
        assertEquals("api.example.com", info.host)
        assertEquals("/v1/accounts?page=2", info.path)
        assertEquals(listOf("Authorization" to "Bearer abc"), info.requestHeaders)
        assertEquals(listOf("Content-Type" to "application/json"), info.responseHeaders)
        assertEquals(5L, info.dnsMs)
        assertEquals("h2", info.protocolName)
        assertEquals(false, info.reusedConnection)
        assertTrue(info.hasTimings)
    }

    @Test
    fun `an entry without a url is not a network row`() {
        // A host logging a plain message into the network category must not render as an empty
        // network row — the capture pipeline always writes `url`.
        val entry = networkEntry(mapOf("note" to "just a message"))
        assertNull(NetworkLogInfo.from(entry))
    }

    @Test
    fun `a non-network category is never parsed`() {
        val entry = LogEntry(
            date = Instant.EPOCH,
            level = LogLevel.INFO,
            category = LogCategory.Auth,
            message = "x",
            metadata = mapOf("url" to "https://a.com")
        )
        assertNull(NetworkLogInfo.from(entry))
    }

    @Test
    fun `failure detection covers errors and 4xx or 5xx`() {
        assertFalse(NetworkLogInfo.from(networkEntry(fullMetadata))!!.isFailure)
        assertTrue(NetworkLogInfo.from(networkEntry(fullMetadata + ("status" to "404")))!!.isFailure)
        assertTrue(NetworkLogInfo.from(networkEntry(fullMetadata + ("error" to "timeout")))!!.isFailure)
    }

    @Test
    fun `the suggested mock pattern drops the query`() {
        val info = NetworkLogInfo.from(networkEntry(fullMetadata))!!
        assertEquals("api.example.com/v1/accounts", info.suggestedMockPattern)
    }

    @Test
    fun `content kind is derived from the response content type`() {
        assertEquals(NetworkContentKind.JSON, NetworkContentKind.of(networkEntry(fullMetadata)))
        assertEquals(
            NetworkContentKind.IMAGE,
            NetworkContentKind.of(networkEntry(fullMetadata + ("respH.Content-Type" to "image/png")))
        )
        // Without a captured Content-Type a record still counts, as "other".
        assertEquals(
            NetworkContentKind.OTHER,
            NetworkContentKind.of(networkEntry(mapOf("url" to "https://a.com")))
        )
    }
}

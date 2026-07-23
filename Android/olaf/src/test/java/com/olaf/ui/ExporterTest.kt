package com.olaf.ui

import com.olaf.LogCategory
import com.olaf.LogEntry
import com.olaf.LogLevel
import com.olaf.ui.model.DecodeAttachmentIndex
import com.olaf.ui.model.NetworkLogInfo
import com.olaf.ui.model.NetworkStats
import com.olaf.ui.util.CurlBuilder
import com.olaf.ui.util.HarExporter
import com.olaf.ui.util.PostmanExporter
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ExporterTest {

    private fun networkEntry(
        url: String = "https://api.example.com/v1/accounts?page=2",
        method: String = "GET",
        status: String = "200",
        extra: Map<String, String> = emptyMap(),
        secondsFromEpoch: Long = 0
    ) = LogEntry(
        date = Instant.ofEpochSecond(secondsFromEpoch),
        level = LogLevel.INFO,
        category = LogCategory.Network,
        message = "$method $url → $status",
        metadata = mapOf(
            "method" to method,
            "url" to url,
            "status" to status,
            "durationMs" to "120",
            "reqBytes" to "10",
            "respBytes" to "2048",
            "reqH.Authorization" to "Bearer abc",
            "reqH.Content-Type" to "application/json",
            "respH.Content-Type" to "application/json",
            "t.dnsMs" to "5",
            "t.connectMs" to "20",
            "t.ttfbMs" to "80",
            "t.protocol" to "h2"
        ) + extra
    )

    // MARK: - HAR

    @Test
    fun `har document has the 1_2 envelope and one entry per record`() {
        val har = JSONObject(HarExporter.harDocument(listOf(networkEntry(), networkEntry(method = "POST"))))
        val log = har.getJSONObject("log")

        assertEquals("1.2", log.getString("version"))
        assertEquals("Olaf", log.getJSONObject("creator").getString("name"))
        assertEquals(2, log.getJSONArray("entries").length())
    }

    @Test
    fun `har entry carries request, response and timings`() {
        val har = JSONObject(HarExporter.harDocument(listOf(networkEntry())))
        val entry = har.getJSONObject("log").getJSONArray("entries").getJSONObject(0)

        val request = entry.getJSONObject("request")
        assertEquals("GET", request.getString("method"))
        assertEquals("HTTP/2", request.getString("httpVersion"))
        assertEquals(1, request.getJSONArray("queryString").length())
        assertEquals("page", request.getJSONArray("queryString").getJSONObject(0).getString("name"))

        assertEquals(200, entry.getJSONObject("response").getInt("status"))

        val timings = entry.getJSONObject("timings")
        assertEquals(5, timings.getInt("dns"))
        assertEquals(80, timings.getInt("wait"))
        // total (120) minus dns+connect+wait (105)
        assertEquals(15, timings.getInt("receive"))
    }

    @Test
    fun `non-network entries are skipped, producing a valid empty document`() {
        val plain = LogEntry(
            date = Instant.EPOCH,
            level = LogLevel.INFO,
            category = LogCategory.General,
            message = "not a request"
        )
        val log = JSONObject(HarExporter.harDocument(listOf(plain))).getJSONObject("log")
        assertEquals(0, log.getJSONArray("entries").length())
    }

    // MARK: - Postman

    @Test
    fun `postman collection deduplicates the same method and url`() {
        val collection = JSONObject(
            PostmanExporter.collection(listOf(networkEntry(), networkEntry(), networkEntry(method = "POST")))
        )
        assertEquals(2, collection.getJSONArray("item").length())
        assertTrue(collection.getJSONObject("info").getString("schema").contains("v2.1.0"))
    }

    @Test
    fun `postman url is split into its parts`() {
        val collection = JSONObject(PostmanExporter.collection(listOf(networkEntry())))
        val url = collection.getJSONArray("item").getJSONObject(0)
            .getJSONObject("request").getJSONObject("url")

        assertEquals("https", url.getString("protocol"))
        assertEquals(listOf("api", "example", "com"), (0 until 3).map { url.getJSONArray("host").getString(it) })
        assertEquals("v1", url.getJSONArray("path").getString(0))
        assertEquals("page", url.getJSONArray("query").getJSONObject(0).getString("key"))
    }

    // MARK: - cURL

    @Test
    fun `curl includes method, headers and body, raw`() {
        val info = NetworkLogInfo.from(
            networkEntry(method = "POST", extra = mapOf("requestBody" to """{"amount":10}"""))
        )!!
        val curl = CurlBuilder.curl(info)

        assertTrue(curl.startsWith("curl -X POST 'https://api.example.com/v1/accounts?page=2'"))
        assertTrue(curl.contains("-H 'Authorization: Bearer abc'"))
        assertTrue(curl.contains("""-d '{"amount":10}'"""))
    }

    @Test
    fun `curl escapes embedded single quotes`() {
        val info = NetworkLogInfo.from(networkEntry(extra = mapOf("requestBody" to "it's")))!!
        assertTrue(CurlBuilder.curl(info).contains("""'it'\''s'"""))
    }

    // MARK: - Statistics

    @Test
    fun `statistics summarise the visible records`() {
        val entries = listOf(
            networkEntry(status = "200"),
            networkEntry(status = "404", url = "https://api.example.com/v1/cards"),
            networkEntry(status = "500", url = "https://other.com/v1/x", method = "POST"),
            networkEntry(status = "200", extra = mapOf("cancelled" to "true"))
        )

        val stats = NetworkStats.compute(entries)
        assertEquals(4, stats.totalRequests)
        assertEquals(2, stats.failureCount) // 404 and 500; cancelled is counted separately
        assertEquals(1, stats.cancelledCount)
        assertEquals(50, stats.failurePercent)
        assertEquals(120L, stats.averageDurationMs)
        assertEquals(listOf("GET" to 3, "POST" to 1), stats.methodCounts)
        // A cancelled call is classed as "Cancelled" rather than by its status code.
        assertEquals(listOf("2xx" to 1, "4xx" to 1, "5xx" to 1, "Cancelled" to 1), stats.statusClassCounts)
        assertEquals("api.example.com", stats.hostCounts.first().first)
    }

    @Test
    fun `statistics over an empty list are safe`() {
        val stats = NetworkStats.compute(emptyList())
        assertEquals(0, stats.totalRequests)
        assertEquals(0, stats.failurePercent)
        assertEquals(null, stats.averageDurationMs)
    }
}

/** Folding decode failures into the network record they belong to. */
class DecodeAttachmentIndexTest {

    private fun entry(
        category: LogCategory,
        url: String,
        secondsFromEpoch: Long,
        message: String = "x"
    ) = LogEntry(
        date = Instant.ofEpochSecond(secondsFromEpoch),
        level = LogLevel.INFO,
        category = category,
        message = message,
        metadata = mapOf("url" to url)
    )

    @Test
    fun `a decode error attaches to the nearest matching request`() {
        val network = entry(LogCategory.Network, "https://api.example.com/v1/accounts?page=2", 100)
        val decode = entry(LogCategory.Decoding, "https://api.example.com/v1/accounts", 101)

        val index = DecodeAttachmentIndex.build(listOf(network, decode))
        assertEquals(listOf(decode.id), index.errors(network).map { it.id })
        assertTrue(decode.id in index.attachedIds)
    }

    @Test
    fun `a decode error far away in time stays unattached`() {
        val network = entry(LogCategory.Network, "https://api.example.com/v1/accounts", 100)
        val decode = entry(LogCategory.Decoding, "https://api.example.com/v1/accounts", 100 + 120)

        val index = DecodeAttachmentIndex.build(listOf(network, decode))
        assertTrue(index.errors(network).isEmpty())
        // Nothing is silently dropped: it keeps rendering as its own row.
        assertTrue(index.attachedIds.isEmpty())
    }

    @Test
    fun `the endpoint key drops scheme and query`() {
        assertEquals(
            "api.example.com/v1/accounts",
            DecodeAttachmentIndex.endpointKey("https://api.example.com/v1/accounts?page=2")
        )
        assertEquals(
            DecodeAttachmentIndex.endpointKey("https://api.example.com/v1/accounts/"),
            DecodeAttachmentIndex.endpointKey("https://api.example.com/v1/accounts")
        )
    }
}

package com.olaf.network

import com.olaf.LogCategory
import com.olaf.LogEntry
import com.olaf.LogLevel
import com.olaf.Olaf
import com.olaf.OlafConfiguration
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException

/**
 * End-to-end capture through a real OkHttp call stack. Instead of a mock web server, the chain is
 * terminated by a stub interceptor that returns a canned response — no sockets, no flakiness,
 * while still exercising the real interceptor plumbing.
 */
class OlafInterceptorTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Before
    fun setUp() {
        // The facade is a process-wide singleton; start is idempotent, so the first test wins and
        // every test clears the buffer for isolation.
        Olaf.runtime.start(
            cacheDir = temporaryFolder.root,
            configuration = OlafConfiguration(persistsToDisk = false, mirrorsToLogcat = false)
        )
        Olaf.clear()
        OlafNetwork.removeAllMocks()
        OlafNetwork.configuration = OlafNetworkConfiguration.Default
        PendingRequestRegistry.removeAll()
    }

    // MARK: - Helpers

    private fun clientReturning(
        code: Int = 200,
        body: String = """{"ok":true}""",
        contentType: String = "application/json"
    ) = client { request ->
        Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(code)
            .message("OK")
            .header("Content-Type", contentType)
            .body(body.toResponseBody(contentType.toMediaType()))
            .build()
    }

    private fun client(terminal: (Request) -> Response) = OkHttpClient.Builder()
        .addInterceptor(OlafNetwork.interceptor())
        .addInterceptor(Interceptor { chain -> terminal(chain.request()) })
        .build()

    private fun get(client: OkHttpClient, url: String = "https://api.example.com/v1/accounts"): Response =
        client.newCall(Request.Builder().url(url).build()).execute()

    private fun networkEntries(): List<LogEntry> =
        Olaf.snapshot().filter { it.category == LogCategory.Network }

    // MARK: - Capture

    @Test
    fun `a successful call is captured with status, url and body`() {
        get(clientReturning()).use { it.body.string() }

        val entry = networkEntries().single()
        assertEquals(LogLevel.INFO, entry.level)
        assertEquals("GET", entry.metadata["method"])
        assertEquals("https://api.example.com/v1/accounts", entry.metadata["url"])
        assertEquals("200", entry.metadata["status"])
        assertTrue(entry.metadata["responseBody"]!!.contains("\"ok\""))
        assertNotNull(entry.metadata["durationMs"])
    }

    @Test
    fun `the caller still receives the body after capture`() {
        // Capture peeks the source, so the response must remain fully readable downstream.
        val body = get(clientReturning(body = """{"value":42}""")).use { it.body.string() }
        assertEquals("""{"value":42}""", body)
    }

    @Test
    fun `json bodies are pretty-printed at capture time`() {
        get(clientReturning(body = """{"a":1,"b":{"c":2}}""")).use { it.body.string() }

        val captured = networkEntries().single().metadata["responseBody"]!!
        assertTrue("expected indented JSON, got: $captured", captured.contains("\n"))
    }

    @Test
    fun `a 500 response is logged at error level`() {
        get(clientReturning(code = 500, body = """{"error":"boom"}""")).use { it.body.string() }
        assertEquals(LogLevel.ERROR, networkEntries().single().level)
    }

    @Test
    fun `a 404 response is logged at warning level`() {
        get(clientReturning(code = 404, body = "{}")).use { it.body.string() }
        assertEquals(LogLevel.WARNING, networkEntries().single().level)
    }

    @Test
    fun `request bodies and headers are captured raw`() {
        val client = clientReturning()
        val request = Request.Builder()
            .url("https://api.example.com/v1/transfer")
            .header("Authorization", "Bearer secret-token")
            .post("""{"amount":10}""".toRequestBody("application/json".toMediaType()))
            .build()
        client.newCall(request).execute().use { it.body.string() }

        val entry = networkEntries().single()
        assertEquals("POST", entry.metadata["method"])
        assertTrue(entry.metadata["requestBody"]!!.contains("amount"))
        // Nothing is masked — that is the whole point of the tool.
        assertEquals("Bearer secret-token", entry.metadata["reqH.Authorization"])
    }

    @Test
    fun `an IO failure is captured as an error and rethrown`() {
        val failing = client { throw IOException("connection reset") }

        assertThrows(IOException::class.java) { get(failing) }

        val entry = networkEntries().single()
        assertEquals(LogLevel.ERROR, entry.level)
        assertEquals("connection reset", entry.metadata["error"])
    }

    @Test
    fun `excluded urls are not captured`() {
        OlafNetwork.configuration = OlafNetworkConfiguration(excludedUrls = listOf("crashlytics"))
        get(clientReturning(), url = "https://api.crashlytics.com/report").use { it.body.string() }
        assertTrue(networkEntries().isEmpty())
    }

    @Test
    fun `body capture can be turned off while the call is still logged`() {
        OlafNetwork.configuration = OlafNetworkConfiguration(capturesBodies = false, capturesHeaders = false)
        get(clientReturning()).use { it.body.string() }

        val entry = networkEntries().single()
        assertEquals("200", entry.metadata["status"])
        assertNull(entry.metadata["responseBody"])
        assertNull(entry.metadata["reqH.Authorization"])
    }

    @Test
    fun `long bodies are truncated to the configured limit`() {
        OlafNetwork.configuration = OlafNetworkConfiguration(maxBodyLength = 50)
        get(clientReturning(body = "x".repeat(500), contentType = "text/plain")).use { it.body.string() }

        val captured = networkEntries().single().metadata["responseBody"]!!
        assertEquals(51, captured.length) // 50 characters plus the ellipsis
        assertTrue(captured.endsWith("…"))
    }

    @Test
    fun `image responses are attached as a base64 preview`() {
        val png = "PNG\r\n\n binary-ish payload"
        get(clientReturning(body = png, contentType = "image/png")).use { it.body.bytes() }

        val entry = networkEntries().single()
        assertNotNull(entry.metadata["responseImageBase64"])
        assertTrue(entry.metadata["responseBody"]!!.startsWith("<"))
    }

    @Test
    fun `the pending registry is emptied once a call completes`() {
        get(clientReturning()).use { it.body.string() }
        assertTrue(OlafNetwork.pendingRequests.isEmpty())
    }

    // MARK: - Mocking

    @Test
    fun `a mock is delivered without reaching the network`() {
        OlafNetwork.addMock(
            OlafMockResponse(urlContains = "mock.olaf-test", statusCode = 418, json = """{"mocked":true}""")
        )
        // The terminal interceptor would fail the test if it were ever reached.
        val client = client { error("the mock should have short-circuited this call") }

        val response = get(client, url = "https://mock.olaf-test/api/v1/accounts")
        val body = response.use { it.body.string() }

        assertEquals(418, response.code)
        assertEquals("application/json", response.header("Content-Type"))
        assertEquals("""{"mocked":true}""", body)

        val entry = networkEntries().single()
        assertEquals("true", entry.metadata["mocked"])
        assertTrue(entry.message.contains("[mock]"))
    }

    @Test
    fun `a mock wins over the exclusion filter`() {
        OlafNetwork.configuration = OlafNetworkConfiguration(excludedUrls = listOf("mocked.example"))
        OlafNetwork.addMock(OlafMockResponse(urlContains = "mocked.example", json = "{}"))

        val client = client { error("the mock should have short-circuited this call") }
        get(client, url = "https://mocked.example/api").use { it.body.string() }

        assertEquals(1, networkEntries().size)
    }

    @Test
    fun `a transport-error mock throws and is logged`() {
        OlafNetwork.addMock(
            OlafMockResponse.failure("fails.example", OlafMockResponse.TransportError.Timeout)
        )
        val client = client { error("the mock should have short-circuited this call") }

        assertThrows(IOException::class.java) { get(client, url = "https://fails.example/api") }

        val entry = networkEntries().single()
        assertEquals(LogLevel.ERROR, entry.level)
        assertEquals("true", entry.metadata["mocked"])
    }

    @Test
    fun `the first matching mock wins`() {
        OlafNetwork.addMock(OlafMockResponse(urlContains = "/v1", statusCode = 201, json = "{}"))
        OlafNetwork.addMock(OlafMockResponse(urlContains = "/v1", statusCode = 500, json = "{}"))

        val client = client { error("the mock should have short-circuited this call") }
        val response = get(client, url = "https://a.com/v1/x")
        response.use { it.body.string() }

        assertEquals(201, response.code)
    }

    @Test
    fun `method-scoped mocks only match that method`() {
        val postOnly = OlafMockResponse(urlContains = "/v1/transfer", method = "post", json = "{}")
        assertTrue(postOnly.matches(Request.Builder().url("https://a.com/v1/transfer").post("".toRequestBody()).build()))
        assertEquals(false, postOnly.matches(Request.Builder().url("https://a.com/v1/transfer").build()))
    }

    @Test
    fun `removing a mock lets the call through again`() {
        val mock = OlafMockResponse(urlContains = "removable.example", json = "{}")
        OlafNetwork.addMock(mock)
        assertEquals(1, OlafNetwork.activeMocks.size)

        OlafNetwork.removeMock(mock.id)
        assertTrue(OlafNetwork.activeMocks.isEmpty())

        get(clientReturning(), url = "https://removable.example/api").use { it.body.string() }
        assertNull(networkEntries().single().metadata["mocked"])
    }
}

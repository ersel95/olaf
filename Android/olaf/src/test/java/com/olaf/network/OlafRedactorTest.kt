package com.olaf.network

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors `OlafRedactorTests.swift` — the two platforms must mask identically. */
class OlafRedactorTest {

    private val keys = listOf("password", "otp", "balance", "iban")

    private fun redactor(
        policy: OlafKeyRedactor.UnparsableBodyPolicy = OlafKeyRedactor.UnparsableBodyPolicy.MaskEntirely,
        substrings: Boolean = true
    ) = OlafKeyRedactor(keys, matchesSubstrings = substrings, unparsableBodyPolicy = policy)

    // MARK: - JSON bodies

    @Test
    fun `masks matching keys and keeps the rest`() {
        val out = redactor().redactBody("""{"userName":"ersel","password":"hunter2","amount":42}""", null)

        assertFalse(out.contains("hunter2"))
        assertTrue(out.contains("***"))
        assertTrue(out.contains("ersel"))
        assertTrue(out.contains("42"))
    }

    @Test
    fun `masks nested objects and arrays`() {
        val body = """{"accounts":[{"iban":"TR12","balance":{"available":100}},{"iban":"TR34"}]}"""
        val out = redactor().redactBody(body, null)

        assertFalse(out.contains("TR12"))
        assertFalse(out.contains("TR34"))
        assertFalse("an entire object under a matching key is masked", out.contains("100"))
    }

    @Test
    fun `substring matching covers derived field names`() {
        val out = redactor().redactBody("""{"availableBalance":100,"otpCode":"123456"}""", null)

        assertFalse(out.contains("100"))
        assertFalse(out.contains("123456"))
    }

    @Test
    fun `exact matching ignores derived names`() {
        val out = redactor(substrings = false).redactBody("""{"availableBalance":100,"balance":7}""", null)

        assertTrue(out.contains("100"))
        assertFalse(out.contains("\"balance\": 7"))
    }

    @Test
    fun `output stays valid json`() {
        val out = redactor().redactBody("""{"password":"x","nested":{"otp":"1"}}""", null)
        assertEquals("***", JSONObject(out).getString("password"))
    }

    // MARK: - Unparsable bodies

    @Test
    fun `unparsable body is masked entirely by default`() {
        // The realistic case is a body truncated by maxBodyLength: matching can't be trusted.
        assertEquals("***", redactor().redactBody("""{"password":"hunter2","amount":4""", null))
    }

    @Test
    fun `keep raw policy leaves unparsable body untouched`() {
        val truncated = """{"password":"hunter2","amount":4"""
        val out = redactor(OlafKeyRedactor.UnparsableBodyPolicy.KeepRaw).redactBody(truncated, null)
        assertEquals(truncated, out)
    }

    @Test
    fun `best effort policy masks key value lines`() {
        val out = redactor(OlafKeyRedactor.UnparsableBodyPolicy.BestEffort)
            .redactBody("password: hunter2\namount: 42", null)

        assertFalse(out.contains("hunter2"))
        assertTrue(out.contains("42"))
    }

    @Test
    fun `empty key list is a no-op`() {
        val body = """{"password":"hunter2"}"""
        assertEquals(body, OlafKeyRedactor(emptyList()).redactBody(body, null))
    }

    // MARK: - Form bodies and URLs

    @Test
    fun `masks form encoded body`() {
        assertEquals("user=ersel&password=***", redactor().redactBody("user=ersel&password=hunter2", null))
    }

    @Test
    fun `masks query string in url`() {
        val out = redactor().redactUrl("https://api.example.com/login?user=ersel&otp=123456")
        assertEquals("https://api.example.com/login?user=ersel&otp=***", out)
    }

    @Test
    fun `url without query is untouched`() {
        val url = "https://api.example.com/accounts"
        assertEquals(url, redactor().redactUrl(url))
    }

    // MARK: - Headers

    @Test
    fun `masks sensitive headers by default`() {
        val r = redactor()
        assertEquals("***", r.redactHeader("Bearer abc", "Authorization", null))
        assertEquals("***", r.redactHeader("sid=1", "cookie", null))
        assertEquals("application/json", r.redactHeader("application/json", "Content-Type", null))
    }

    // MARK: - Composer wiring (the single choke point)

    private fun event() = NetworkLogEvent(
        method = "POST",
        url = "https://api.example.com/transfer?otp=999",
        statusCode = 200,
        durationMs = 12
    ).apply {
        requestBody = """{"password":"hunter2"}"""
        responseBody = """{"balance":5000}"""
        requestHeaders = mapOf("Authorization" to "Bearer abc", "Accept" to "application/json")
    }

    @Test
    fun `composer applies redactor to bodies headers and url`() {
        val metadata = NetworkLogComposer.metadata(event(), redactor())

        assertFalse(metadata["requestBody"]!!.contains("hunter2"))
        assertFalse(metadata["responseBody"]!!.contains("5000"))
        assertEquals("***", metadata["reqH.Authorization"])
        assertEquals("application/json", metadata["reqH.Accept"])
        assertFalse(metadata["url"]!!.contains("999"))
    }

    @Test
    fun `composer without redactor stores everything raw`() {
        // The default stays raw — non-prod debugging depends on it.
        val metadata = NetworkLogComposer.metadata(event())

        assertTrue(metadata["requestBody"]!!.contains("hunter2"))
        assertTrue(metadata["responseBody"]!!.contains("5000"))
        assertEquals("Bearer abc", metadata["reqH.Authorization"])
        assertTrue(metadata["url"]!!.contains("999"))
    }

    @Test
    fun `message url is redacted`() {
        assertFalse(NetworkLogComposer.message(event(), redactor()).contains("999"))
    }

    @Test
    fun `configuration defaults to no redactor`() {
        assertNull(OlafNetworkConfiguration.Default.redactor)
    }
}

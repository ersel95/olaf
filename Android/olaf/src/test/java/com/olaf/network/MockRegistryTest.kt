package com.olaf.network

import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The three mocking layers and their precedence, mirroring `MockingTests` on iOS: an endpoint's
 * active variant wins, an endpoint on Original bypasses everything including the global override,
 * and only then does the global override apply.
 */
class MockRegistryTest {

    @After
    fun tearDown() {
        // Full teardown, templates and scenarios included — `removeAllMocks()` deliberately keeps
        // the library, which would otherwise leak between tests.
        MockRegistry.removeAll()
    }

    private fun request(url: String, method: String = "GET"): Request {
        // OkHttp rejects a null body on methods that require one, so give those an empty body.
        val body = if (method == "GET" || method == "HEAD") null else ByteArray(0).toRequestBody()
        return Request.Builder().url(url).method(method, body).build()
    }

    // MARK: - Variants and endpoint reset

    @Test
    fun `selecting a variant switches the served response`() {
        val success = OlafMockVariant("Success", OlafMockPayload.json("""{"ok":true}"""))
        val failure = OlafMockVariant("500", OlafMockPayload.json("{}", statusCode = 500))
        val endpointId = OlafNetwork.addEndpoint(
            OlafMockEndpoint(
                urlContains = "api.example.com/v1/pay",
                variants = listOf(success, failure),
                activeVariantId = success.id
            )
        )

        val target = request("https://api.example.com/v1/pay")
        assertEquals(200, OlafNetwork.mock(target)?.statusCode)

        OlafNetwork.selectVariant(failure.id, endpointId)
        assertEquals(500, OlafNetwork.mock(target)?.statusCode)

        // Both variants stay saved — switching is not destructive.
        assertEquals(listOf("Success", "500"), OlafNetwork.mockEndpoints.first().variants.map { it.name })
    }

    @Test
    fun `resetting an endpoint falls back to the real network and keeps its variants`() {
        val variant = OlafMockVariant("Empty", OlafMockPayload.json("""{"items":[]}"""))
        val endpointId = OlafNetwork.addEndpoint(
            OlafMockEndpoint(
                urlContains = "api.example.com/v1/list",
                variants = listOf(variant),
                activeVariantId = variant.id
            )
        )
        val target = request("https://api.example.com/v1/list")
        assertEquals(200, OlafNetwork.mock(target)?.statusCode)

        OlafNetwork.resetEndpoint(endpointId)

        assertNull(OlafNetwork.mock(target))
        assertEquals(1, OlafNetwork.mockEndpoints.first().variants.size)
        assertTrue(OlafNetwork.activeMocks.isEmpty())

        // ...and it can be switched straight back on.
        OlafNetwork.selectVariant(variant.id, endpointId)
        assertEquals(200, OlafNetwork.mock(target)?.statusCode)
    }

    @Test
    fun `removing the served variant falls back to Original`() {
        val variant = OlafMockVariant("Empty", OlafMockPayload.json("{}"))
        val endpointId = OlafNetwork.addEndpoint(
            OlafMockEndpoint(
                urlContains = "api.example.com/v1/x",
                variants = listOf(variant),
                activeVariantId = variant.id
            )
        )

        OlafNetwork.removeVariant(variant.id, endpointId)

        assertNull(OlafNetwork.mock(request("https://api.example.com/v1/x")))
        assertNull(OlafNetwork.mockEndpoints.first().activeVariantId)
    }

    @Test
    fun `a variant resets to the response it was captured with`() {
        val captured = OlafMockPayload.json("""{"balance":42}""")
        val variant = OlafMockVariant("Captured", captured)
        assertFalse(variant.isModified)

        val edited = variant.copy(payload = OlafMockPayload.json("boom", statusCode = 500))
        assertTrue(edited.isModified)

        assertEquals(captured, edited.resetToCaptured().payload)
        assertFalse(edited.resetToCaptured().isModified)
    }

    @Test
    fun `editing a variant keeps its captured payload`() {
        val captured = OlafMockPayload.json("{}")
        val variant = OlafMockVariant("Captured", captured)
        val endpointId = OlafNetwork.addEndpoint(
            OlafMockEndpoint(
                urlContains = "api.example.com/v1/y",
                variants = listOf(variant),
                activeVariantId = variant.id
            )
        )

        OlafNetwork.updateVariant(variant.id, endpointId) { stored ->
            stored.copy(name = "Renamed", payload = stored.payload.copy(statusCode = 503))
        }

        val stored = OlafNetwork.mockEndpoints.first().variants.first()
        assertEquals("Renamed", stored.name)
        assertEquals(503, stored.payload.statusCode)
        assertEquals(captured, stored.capturedPayload)   // reset still has something to restore
        assertTrue(stored.isModified)
    }

    // MARK: - Global override

    @Test
    fun `the global override applies only where no endpoint entry exists`() {
        val templateId = OlafNetwork.addTemplate(
            OlafMockTemplate("All 500", OlafMockPayload.json("{}", statusCode = 500))
        )
        OlafNetwork.globalMockTemplateId = templateId

        // No endpoint entry → the global override is served.
        assertEquals(500, OlafNetwork.mock(request("https://anything.example/x"))?.statusCode)

        // An endpoint with an active variant wins over the global override.
        val variant = OlafMockVariant("OK", OlafMockPayload.json("{}"))
        val endpointId = OlafNetwork.addEndpoint(
            OlafMockEndpoint(
                urlContains = "api.example.com/v1/ok",
                variants = listOf(variant),
                activeVariantId = variant.id
            )
        )
        assertEquals(200, OlafNetwork.mock(request("https://api.example.com/v1/ok"))?.statusCode)

        // An endpoint on Original is a deliberate "leave this alone" — the global override skips it.
        OlafNetwork.resetEndpoint(endpointId)
        assertNull(OlafNetwork.mock(request("https://api.example.com/v1/ok")))
        assertEquals(500, OlafNetwork.mock(request("https://other.example/x"))?.statusCode)
    }

    @Test
    fun `resolution reports the layer that matched`() {
        val templateId = OlafNetwork.addTemplate(
            OlafMockTemplate("All 500", OlafMockPayload.json("{}", statusCode = 500))
        )
        OlafNetwork.globalMockTemplateId = templateId
        val variant = OlafMockVariant("OK", OlafMockPayload.json("{}"))
        val endpointId = OlafNetwork.addEndpoint(
            OlafMockEndpoint(
                urlContains = "api.example.com/v1/ok",
                variants = listOf(variant),
                activeVariantId = variant.id
            )
        )

        // The interceptor keys off these cases: only Endpoint overrides the capture filters.
        assertTrue(OlafNetwork.mockResolution(request("https://api.example.com/v1/ok")) is MockResolution.Endpoint)
        assertTrue(OlafNetwork.mockResolution(request("https://other.example/x")) is MockResolution.Global)

        OlafNetwork.resetEndpoint(endpointId)
        assertTrue(OlafNetwork.mockResolution(request("https://api.example.com/v1/ok")) is MockResolution.Bypass)

        OlafNetwork.globalMockTemplateId = null
        assertTrue(OlafNetwork.mockResolution(request("https://other.example/x")) is MockResolution.None)
    }

    @Test
    fun `removing a template clears it as the global override`() {
        val templateId = OlafNetwork.addTemplate(
            OlafMockTemplate("Custom", OlafMockPayload.json("{}", statusCode = 503))
        )
        OlafNetwork.globalMockTemplateId = templateId
        assertEquals(503, OlafNetwork.mock(request("https://a.com/x"))?.statusCode)

        OlafNetwork.removeTemplate(templateId)

        assertNull(OlafNetwork.globalMockTemplateId)
        assertNull(OlafNetwork.mock(request("https://a.com/x")))
    }

    @Test
    fun `built-in templates are available and cannot be deleted`() {
        val builtIn = OlafNetwork.mockTemplates
        assertTrue(builtIn.isNotEmpty())
        assertTrue(builtIn.all { it.isBuiltIn })

        OlafNetwork.removeTemplate(builtIn[0].id)
        assertEquals(builtIn.size, OlafNetwork.mockTemplates.size)
    }

    // MARK: - Scenarios

    @Test
    fun `a scenario captures and restores every selection`() {
        val listEmpty = OlafMockVariant("Empty", OlafMockPayload.json("""{"items":[]}"""))
        val listFull = OlafMockVariant("Full", OlafMockPayload.json("""{"items":[1]}"""))
        val listId = OlafNetwork.addEndpoint(
            OlafMockEndpoint(
                urlContains = "api.example.com/list",
                variants = listOf(listEmpty, listFull),
                activeVariantId = listEmpty.id
            )
        )
        val payFail = OlafMockVariant("500", OlafMockPayload.json("{}", statusCode = 500))
        val payId = OlafNetwork.addEndpoint(
            OlafMockEndpoint(
                urlContains = "api.example.com/pay",
                variants = listOf(payFail),
                activeVariantId = payFail.id
            )
        )
        val templateId = OlafNetwork.addTemplate(
            OlafMockTemplate("All 500", OlafMockPayload.json("{}", statusCode = 500))
        )
        OlafNetwork.globalMockTemplateId = templateId

        val scenario = OlafNetwork.saveScenario("Empty state")
        assertEquals(2, scenario.selections.size)

        // Drift away from it...
        OlafNetwork.selectVariant(listFull.id, listId)
        OlafNetwork.resetEndpoint(payId)
        OlafNetwork.globalMockTemplateId = null

        // ...then come back.
        OlafNetwork.applyScenario(scenario.id)

        assertEquals(
            """{"items":[]}""",
            OlafNetwork.mock(request("https://api.example.com/list"))?.body?.toString(Charsets.UTF_8)
        )
        assertEquals(500, OlafNetwork.mock(request("https://api.example.com/pay"))?.statusCode)
        assertEquals(templateId, OlafNetwork.globalMockTemplateId)
    }

    @Test
    fun `applying a scenario resets endpoints it does not name`() {
        val first = OlafMockVariant("A", OlafMockPayload.json("{}", statusCode = 201))
        val firstId = OlafNetwork.addEndpoint(
            OlafMockEndpoint("api.example.com/a", variants = listOf(first), activeVariantId = first.id)
        )
        val scenario = OlafNetwork.saveScenario("Only A")

        // An endpoint that didn't exist when the scenario was saved.
        val second = OlafMockVariant("B", OlafMockPayload.json("{}", statusCode = 202))
        val secondId = OlafNetwork.addEndpoint(
            OlafMockEndpoint("api.example.com/b", variants = listOf(second), activeVariantId = second.id)
        )

        OlafNetwork.applyScenario(scenario.id)

        assertEquals(first.id, OlafNetwork.mockEndpoints.first { it.id == firstId }.activeVariantId)
        assertNull(OlafNetwork.mockEndpoints.first { it.id == secondId }.activeVariantId)
    }

    @Test
    fun `a scenario falls back to Original when the variant was deleted`() {
        val variant = OlafMockVariant("A", OlafMockPayload.json("{}"))
        val endpointId = OlafNetwork.addEndpoint(
            OlafMockEndpoint("api.example.com/a", variants = listOf(variant), activeVariantId = variant.id)
        )
        val scenario = OlafNetwork.saveScenario("With A")

        OlafNetwork.removeVariant(variant.id, endpointId)
        OlafNetwork.applyScenario(scenario.id)

        assertNull(OlafNetwork.mockEndpoints.first().activeVariantId)
        assertNull(OlafNetwork.mock(request("https://api.example.com/a")))
    }

    // MARK: - Bulk reset

    @Test
    fun `reset all keeps definitions while remove all drops them`() {
        val variant = OlafMockVariant("A", OlafMockPayload.json("{}"))
        OlafNetwork.addEndpoint(
            OlafMockEndpoint("api.example.com/a", variants = listOf(variant), activeVariantId = variant.id)
        )
        OlafNetwork.globalMockTemplateId = OlafNetwork.mockTemplates[0].id

        OlafNetwork.resetAllToOriginal()
        assertNull(OlafNetwork.globalMockTemplateId)
        assertEquals(1, OlafNetwork.mockEndpoints.size)          // kept
        assertEquals(1, OlafNetwork.mockEndpoints.first().variants.size)
        assertNull(OlafNetwork.mock(request("https://api.example.com/a")))

        OlafNetwork.removeAllMocks()
        assertTrue(OlafNetwork.mockEndpoints.isEmpty())          // gone
        assertTrue(OlafNetwork.mockTemplates.isNotEmpty())       // library survives
    }

    // MARK: - Legacy one-shot API

    @Test
    fun `a legacy mock becomes an endpoint with one active variant`() {
        val mock = OlafMockResponse(urlContains = "/v1/legacy", json = "{}", statusCode = 204)
        OlafNetwork.addMock(mock)

        val endpoint = OlafNetwork.mockEndpoints.first()
        assertEquals(mock.id, endpoint.id)                       // the id handed out still addresses it
        assertEquals(1, endpoint.variants.size)
        assertEquals(endpoint.variants.first().id, endpoint.activeVariantId)
        assertEquals(listOf(204), OlafNetwork.activeMocks.map { it.statusCode })

        // Adding a second variant to a legacy-created endpoint works like any other.
        OlafNetwork.addVariant(OlafMockVariant("500", OlafMockPayload.json("{}", statusCode = 500)), mock.id)
        assertEquals(500, OlafNetwork.mock(request("https://a.com/v1/legacy"))?.statusCode)
    }

    @Test
    fun `removeMock accepts a variant id too`() {
        val variant = OlafMockVariant("A", OlafMockPayload.json("{}"))
        OlafNetwork.addEndpoint(
            OlafMockEndpoint("api.example.com/a", variants = listOf(variant), activeVariantId = variant.id)
        )

        OlafNetwork.removeMock(variant.id)

        assertEquals(1, OlafNetwork.mockEndpoints.size)          // the endpoint stays
        assertTrue(OlafNetwork.mockEndpoints.first().variants.isEmpty())
        assertNull(OlafNetwork.mock(request("https://api.example.com/a")))
    }

    @Test
    fun `matching honours the method and is case-insensitive on the URL`() {
        val variant = OlafMockVariant("A", OlafMockPayload.json("{}"))
        OlafNetwork.addEndpoint(
            OlafMockEndpoint(
                urlContains = "/V1/Transfer",
                method = "post",
                variants = listOf(variant),
                activeVariantId = variant.id
            )
        )

        assertEquals(200, OlafNetwork.mock(request("https://a.com/v1/transfer", "POST"))?.statusCode)
        assertNull(OlafNetwork.mock(request("https://a.com/v1/transfer", "GET")))
    }
}

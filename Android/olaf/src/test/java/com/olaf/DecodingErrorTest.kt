package com.olaf

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class DecodingErrorTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Before
    fun setUp() {
        Olaf.runtime.start(
            cacheDir = temporaryFolder.root,
            configuration = OlafConfiguration(persistsToDisk = false, mirrorsToLogcat = false)
        )
        Olaf.clear()
    }

    @Test
    fun `the failing field path is lifted out of a gson message`() {
        val error = IllegalStateException(
            "Expected BEGIN_OBJECT but was STRING at line 1 column 34 path \$.user.accounts[0].iban"
        )
        val described = DecodingErrorDescriber.describe(error)
        assertEquals("\$.user.accounts[0].iban", described.path)
    }

    @Test
    fun `a moshi style message is understood too`() {
        val described = DecodingErrorDescriber.describe(
            IllegalStateException("Expected a string but was BEGIN_OBJECT at path \$.data.name")
        )
        assertEquals("\$.data.name", described.path)
    }

    @Test
    fun `a message without a path falls back to the plain detail`() {
        val described = DecodingErrorDescriber.describe(IllegalStateException("something went wrong"))
        assertNull(described.path)
        assertEquals("something went wrong", described.detail)
    }

    @Test
    fun `logDecodingError writes path, type, url and body`() {
        Olaf.logDecodingError(
            error = IllegalStateException("Expected BEGIN_OBJECT but was STRING at path \$.iban"),
            url = "https://api.example.com/v1/accounts",
            body = """{"iban": 42}""",
            typeName = "Account"
        )

        val entry = Olaf.snapshot().single()
        assertEquals(LogLevel.ERROR, entry.level)
        assertEquals(LogCategory.Decoding, entry.category)
        assertEquals("\$.iban", entry.metadata["decoding.path"])
        assertEquals("Account", entry.metadata["decoding.type"])
        // The url key is what lets the viewer fold this into its network row.
        assertEquals("https://api.example.com/v1/accounts", entry.metadata["url"])
        assertEquals("""{"iban": 42}""", entry.metadata["responseBody"])
        assertTrue(entry.message.contains("Account"))
        assertTrue(entry.message.contains("\$.iban"))
    }
}

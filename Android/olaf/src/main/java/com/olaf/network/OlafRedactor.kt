package com.olaf.network

import org.json.JSONArray
import org.json.JSONObject

/**
 * Masks sensitive values before a captured call is recorded.
 *
 * Olaf knows nothing about *what* is sensitive — that is domain knowledge and stays with the host
 * (this is a public repository; see the "no bank or company names" rule). The library only fixes
 * *where* masking happens: every captured body, header and URL passes through the redactor in
 * [NetworkLogComposer.metadata], the single point where a network event becomes a stored record.
 * Nothing bypasses it, so a host never wires filtering up per endpoint.
 *
 * Redaction runs at **capture time**, so the raw value never reaches the NDJSON session file.
 *
 * ```kotlin
 * OlafNetwork.configuration = OlafNetworkConfiguration(
 *     redactor = if (isLiveEnvironment) OlafKeyRedactor(listOf("password", "otp")) else null
 * )
 * ```
 *
 * Mirrors `OlafRedactor` in the iOS package — keep the two in step.
 *
 * Note: masking is a *denylist*. A field the redactor doesn't recognise is stored raw, so for a
 * build that must not leak anything, don't capture at all rather than leaning on a redactor.
 */
interface OlafRedactor {

    /** Masks a request or response body. [url] allows endpoint-specific rules; most ignore it. */
    fun redactBody(body: String, url: String?): String

    /** Masks a single header value. [name] keeps the casing it was captured with. */
    fun redactHeader(value: String, name: String, url: String?): String = value

    /** Masks the URL itself, for values that travel in the query string. */
    fun redactUrl(url: String): String = url
}

/**
 * A ready-made [OlafRedactor] that masks values by **field name** across JSON bodies, form bodies
 * and query strings. The names come from the host, so the library stays domain-agnostic.
 *
 * Matching is case-insensitive and substring-based by default: `"balance"` also covers
 * `"availableBalance"`. Nested objects and arrays are walked in full.
 */
class OlafKeyRedactor(
    keys: List<String>,
    headerNames: List<String> = listOf("authorization", "cookie", "set-cookie", "x-api-key"),
    /** Text a masked value is replaced with. */
    private val placeholder: String = "***",
    /** Substring match (default) or exact equality. */
    private val matchesSubstrings: Boolean = true,
    /** What to do with a body that is neither JSON nor form-encoded. */
    private val unparsableBodyPolicy: UnparsableBodyPolicy = UnparsableBodyPolicy.MaskEntirely
) : OlafRedactor {

    /**
     * Behaviour for a body that field-name matching can't be applied to reliably — most often a
     * body truncated by `maxBodyLength`.
     */
    enum class UnparsableBodyPolicy {
        /** Replace the whole body with the placeholder. **Default**: fails closed. */
        MaskEntirely,

        /** Best-effort `key: value` / `key = value` pass, keeping the rest. Weaker guarantees. */
        BestEffort,

        /** Store the body raw. Only for hosts that know their traffic is JSON. */
        KeepRaw
    }

    private val keys = keys.map { it.lowercase() }
    private val headerNames = headerNames.map { it.lowercase() }

    /** Does this field name match one of the configured keys? */
    fun matches(key: String): Boolean {
        val candidate = key.lowercase()
        return if (matchesSubstrings) keys.any { candidate.contains(it) } else keys.contains(candidate)
    }

    override fun redactBody(body: String, url: String?): String {
        if (body.isEmpty() || keys.isEmpty()) return body

        redactJson(body)?.let { return it }
        if (body.contains("=") && !body.contains("\n")) return redactQuery(body)

        return when (unparsableBodyPolicy) {
            UnparsableBodyPolicy.MaskEntirely -> placeholder
            UnparsableBodyPolicy.BestEffort -> redactTextually(body)
            UnparsableBodyPolicy.KeepRaw -> body
        }
    }

    override fun redactHeader(value: String, name: String, url: String?): String =
        if (headerNames.contains(name.lowercase()) || matches(name)) placeholder else value

    override fun redactUrl(url: String): String {
        if (keys.isEmpty()) return url
        val separator = url.indexOf('?')
        if (separator < 0) return url
        return url.substring(0, separator + 1) + redactQuery(url.substring(separator + 1))
    }

    // MARK: - JSON

    /** Returns null when the body isn't valid JSON, so the caller can fall back to its policy. */
    private fun redactJson(body: String): String? {
        val trimmed = body.trim()
        return try {
            when {
                trimmed.startsWith("{") -> redactObject(JSONObject(trimmed), maskAll = false).toString(2)
                trimmed.startsWith("[") -> redactArray(JSONArray(trimmed), maskAll = false).toString(2)
                else -> null
            }
        } catch (_: org.json.JSONException) {
            null
        }
    }

    /**
     * [maskAll] latches on once a matching key is seen, so an entire nested object under e.g.
     * `"balance"` is masked rather than only its scalar leaves.
     */
    private fun redactObject(source: JSONObject, maskAll: Boolean): JSONObject {
        val out = JSONObject()
        for (key in source.keys()) {
            out.put(key, redactValue(source.get(key), maskAll || matches(key)))
        }
        return out
    }

    private fun redactArray(source: JSONArray, maskAll: Boolean): JSONArray {
        val out = JSONArray()
        for (index in 0 until source.length()) {
            out.put(redactValue(source.get(index), maskAll))
        }
        return out
    }

    private fun redactValue(value: Any?, maskAll: Boolean): Any = when (value) {
        is JSONObject -> redactObject(value, maskAll)
        is JSONArray -> redactArray(value, maskAll)
        else -> if (maskAll) placeholder else (value ?: JSONObject.NULL)
    }

    // MARK: - Form / query

    private fun redactQuery(query: String): String =
        query.split("&").joinToString("&") { pair ->
            val equals = pair.indexOf('=')
            if (equals < 0) return@joinToString pair
            val name = pair.substring(0, equals)
            if (matches(name)) "$name=$placeholder" else pair
        }

    // MARK: - Textual fallback

    /** Line-oriented masking for non-JSON, non-form bodies. Best-effort by definition. */
    private fun redactTextually(body: String): String =
        body.split("\n").joinToString("\n") { line ->
            val separator = line.indexOfFirst { it == ':' || it == '=' }
            if (separator < 0) return@joinToString line
            val name = line.substring(0, separator).trim().trim('"', '\'')
            if (!matches(name)) return@joinToString line
            val leading = line.takeWhile { it == ' ' || it == '\t' }
            "$leading$name${line[separator]} $placeholder"
        }
}

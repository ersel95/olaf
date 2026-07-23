package com.olaf.ui.util

import com.olaf.LogEntry
import com.olaf.ui.model.NetworkLogInfo
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Converts the visible network entries into a **Postman Collection v2.1** document, which can be
 * brought straight into Postman via Import and re-run.
 *
 * The same `method + URL` pair is added once — the first occurrence wins — so repeated calls don't
 * bloat the collection. Header and body values are **raw**, including `Authorization`, so review
 * before sharing.
 */
internal object PostmanExporter {

    fun collection(entries: List<LogEntry>, name: String = "Olaf Export"): String {
        val seen = mutableSetOf<String>()
        val items = JSONArray()

        for (entry in entries) {
            val info = NetworkLogInfo.from(entry) ?: continue
            val url = info.url ?: continue
            val method = (info.method ?: "GET").uppercase()
            if (!seen.add("$method $url")) continue
            items.put(item(info, method, url))
        }

        val info = JSONObject()
            .put("name", name)
            .put("_postman_id", UUID.randomUUID().toString().lowercase())
            .put("schema", "https://schema.getpostman.com/json/collection/v2.1.0/collection.json")

        return JSONObject().put("info", info).put("item", items).toString(2)
    }

    private fun item(info: NetworkLogInfo, method: String, url: String): JSONObject {
        val headers = JSONArray()
        info.requestHeaders.forEach { (key, value) ->
            headers.put(JSONObject().put("key", key).put("value", value))
        }

        val request = JSONObject()
            .put("method", method)
            .put("header", headers)
            .put("url", urlObject(url))

        info.requestBody?.takeIf { it.isNotEmpty() }?.let { body ->
            val contentType = info.requestHeaders
                .firstOrNull { it.first.equals("Content-Type", ignoreCase = true) }
                ?.second
                .orEmpty()
            val bodyObject = JSONObject().put("mode", "raw").put("raw", body)
            if (contentType.lowercase().contains("json") || looksLikeJson(body)) {
                bodyObject.put("options", JSONObject().put("raw", JSONObject().put("language", "json")))
            }
            request.put("body", bodyObject)
        }

        return JSONObject()
            .put("name", "$method ${info.path}")
            .put("request", request)
    }

    /** Postman's structured URL object: the raw string plus its parts. */
    private fun urlObject(url: String): JSONObject {
        val json = JSONObject().put("raw", url)

        val scheme = url.substringBefore("://", "")
        if (scheme.isNotEmpty()) json.put("protocol", scheme)

        val afterScheme = url.substringAfter("://", url)
        val authority = afterScheme.substringBefore('/').substringBefore('?')
        val hostPart = authority.substringBefore(':')
        if (hostPart.isNotEmpty()) {
            json.put("host", JSONArray(hostPart.split('.')))
        }
        authority.substringAfter(':', "").takeIf { it.isNotEmpty() }?.let { json.put("port", it) }

        val pathAndQuery = afterScheme.substringAfter('/', "")
        val path = pathAndQuery.substringBefore('?').split('/').filter { it.isNotEmpty() }
        if (path.isNotEmpty()) json.put("path", JSONArray(path))

        val query = pathAndQuery.substringAfter('?', "")
        if (query.isNotEmpty()) {
            val queryArray = JSONArray()
            query.split('&').forEach { pair ->
                if (pair.isEmpty()) return@forEach
                queryArray.put(
                    JSONObject()
                        .put("key", pair.substringBefore('='))
                        .put("value", pair.substringAfter('=', ""))
                )
            }
            json.put("query", queryArray)
        }

        return json
    }

    private fun looksLikeJson(text: String): Boolean {
        val trimmed = text.trim()
        return trimmed.startsWith("{") || trimmed.startsWith("[")
    }
}

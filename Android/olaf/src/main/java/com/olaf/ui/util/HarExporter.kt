package com.olaf.ui.util

import com.olaf.LogEntry
import com.olaf.ui.model.NetworkLogInfo
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Converts the visible network entries into a **HAR 1.2** document, which opens directly in
 * Charles, Proxyman or Chrome DevTools.
 *
 * The source is the metadata captured at request time; fields that cannot be measured exactly use
 * the spec's "unknown" value (`-1`). Bodies are written as captured — possibly truncated and
 * pretty-printed — and are **raw**, so review before sharing.
 */
internal object HarExporter {

    private val timestampFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

    /** Produces HAR JSON. Entries that aren't network records are skipped. */
    fun harDocument(entries: List<LogEntry>): String {
        val harEntries = JSONArray()
        entries.forEach { entry ->
            NetworkLogInfo.from(entry)?.let { harEntries.put(harEntry(it, entry.date)) }
        }

        val log = JSONObject()
            .put("version", "1.2")
            .put("creator", JSONObject().put("name", "Olaf").put("version", "-"))
            .put("entries", harEntries)

        return JSONObject().put("log", log).toString(2)
    }

    private fun harEntry(info: NetworkLogInfo, date: Instant): JSONObject {
        val total = info.durationMs ?: 0
        // Per the HAR contract `connect` already encompasses `ssl`, so the known phases are
        // dns + connect + wait; whatever is left over is time spent receiving.
        val known = (info.dnsMs ?: 0) + (info.connectMs ?: 0) + (info.ttfbMs ?: 0)
        val receive = (total - known).coerceAtLeast(0)

        val request = JSONObject()
            .put("method", info.method ?: "GET")
            .put("url", info.url.orEmpty())
            .put("httpVersion", httpVersion(info.protocolName))
            .put("cookies", JSONArray())
            .put("headers", harHeaders(info.requestHeaders))
            .put("queryString", queryString(info.url))
            .put("headersSize", -1)
            .put("bodySize", info.requestBytes ?: -1)

        info.requestBody?.takeIf { it.isNotEmpty() }?.let { body ->
            request.put(
                "postData",
                JSONObject()
                    .put("mimeType", headerValue(info.requestHeaders, "Content-Type") ?: "application/octet-stream")
                    .put("text", body)
            )
        }

        val response = JSONObject()
            .put("status", info.statusCode ?: 0)
            .put("statusText", info.error ?: if (info.cancelled) "cancelled" else "")
            .put("httpVersion", httpVersion(info.protocolName))
            .put("cookies", JSONArray())
            .put("headers", harHeaders(info.responseHeaders))
            .put(
                "content",
                JSONObject()
                    .put("size", info.responseBytes ?: -1)
                    .put("mimeType", headerValue(info.responseHeaders, "Content-Type") ?: "application/octet-stream")
                    .put("text", info.responseBody.orEmpty())
            )
            .put("redirectURL", "")
            .put("headersSize", -1)
            .put("bodySize", info.responseBytes ?: -1)

        val timings = JSONObject()
            .put("blocked", -1)
            .put("dns", info.dnsMs ?: -1)
            .put("connect", info.connectMs ?: -1)
            .put("send", 0)
            .put("wait", info.ttfbMs ?: -1)
            .put("receive", receive)
            .put("ssl", info.tlsMs ?: -1)

        return JSONObject()
            .put("startedDateTime", timestampFormatter.format(date))
            .put("time", total)
            .put("request", request)
            .put("response", response)
            .put("cache", JSONObject())
            .put("timings", timings)
    }

    private fun harHeaders(headers: List<Pair<String, String>>): JSONArray {
        val array = JSONArray()
        headers.forEach { (name, value) ->
            array.put(JSONObject().put("name", name).put("value", value))
        }
        return array
    }

    private fun headerValue(headers: List<Pair<String, String>>, name: String): String? =
        headers.firstOrNull { it.first.equals(name, ignoreCase = true) }?.second

    private fun queryString(url: String?): JSONArray {
        val array = JSONArray()
        val query = url?.substringAfter('?', "").orEmpty()
        if (query.isEmpty()) return array
        query.split('&').forEach { pair ->
            if (pair.isEmpty()) return@forEach
            array.put(
                JSONObject()
                    .put("name", pair.substringBefore('='))
                    .put("value", pair.substringAfter('=', ""))
            )
        }
        return array
    }

    /** Maps the ALPN name onto the representation HAR expects. */
    private fun httpVersion(protocolName: String?): String = when (protocolName?.lowercase()) {
        "h2" -> "HTTP/2"
        "h3" -> "HTTP/3"
        null, "" -> "HTTP/1.1"
        else -> protocolName
    }
}

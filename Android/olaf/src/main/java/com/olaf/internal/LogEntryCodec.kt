package com.olaf.internal

import com.olaf.LogCategory
import com.olaf.LogEntry
import com.olaf.LogLevel
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * NDJSON codec for [LogEntry] — one JSON object per line.
 *
 * The field names match the iOS package's on-disk schema (`sessionID`, `level` as an ordinal,
 * `category` as its raw string), so the same tooling — `jq`, log pipelines — works against
 * either platform's export. Timestamps are written with millisecond precision; parsing accepts
 * any ISO-8601 instant, including the second-precision form iOS writes.
 */
internal object LogEntryCodec {

    private val timestampFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

    fun encode(entry: LogEntry): String {
        val json = JSONObject()
        json.put("id", entry.id)
        json.put("date", timestampFormatter.format(entry.date))
        json.put("level", entry.level.ordinal)
        json.put("category", entry.category.rawValue)
        json.put("message", entry.message)
        json.put("metadata", JSONObject(entry.metadata as Map<*, *>))
        json.put("file", entry.file)
        json.put("line", entry.line)
        json.put("function", entry.function)
        json.put("thread", entry.thread)
        json.put("sessionID", entry.sessionId)
        return json.toString()
    }

    /** Returns `null` for corrupt lines — a damaged line must never break history reading. */
    fun decode(line: String): LogEntry? = try {
        val json = JSONObject(line)
        LogEntry(
            id = json.optString("id").ifEmpty { java.util.UUID.randomUUID().toString() },
            date = parseInstant(json.optString("date")),
            level = LogLevel.fromOrdinal(json.optInt("level", LogLevel.INFO.ordinal)),
            category = LogCategory(json.optString("category").ifEmpty { "general" }),
            message = json.optString("message"),
            metadata = decodeMetadata(json.optJSONObject("metadata")),
            file = json.optString("file"),
            line = json.optInt("line"),
            function = json.optString("function"),
            thread = json.optString("thread"),
            sessionId = json.optString("sessionID")
        )
    } catch (_: Throwable) {
        null
    }

    private fun decodeMetadata(json: JSONObject?): Map<String, String> {
        if (json == null || json.length() == 0) return emptyMap()
        val result = LinkedHashMap<String, String>(json.length())
        for (key in json.keys()) {
            result[key] = json.optString(key)
        }
        return result
    }

    private fun parseInstant(raw: String): Instant =
        if (raw.isEmpty()) Instant.EPOCH else runCatching { Instant.parse(raw) }.getOrDefault(Instant.EPOCH)
}

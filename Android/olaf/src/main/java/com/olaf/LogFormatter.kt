package com.olaf

import com.olaf.internal.LogEntryCodec
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Strategy for turning a [LogEntry] into text. The viewer and the `.log` export use the
 * plain-text formatter; the NDJSON export uses [JsonLogFormatter].
 */
fun interface LogFormatter {
    fun format(entry: LogEntry): String
}

/**
 * Human-readable single-line format:
 * `HH:mm:ss.SSS [LEVEL] [category] message {k=v} (File.kt:line)`
 */
class PlainTextFormatter(
    private val includesMetadata: Boolean = true,
    private val includesSource: Boolean = true
) : LogFormatter {

    override fun format(entry: LogEntry): String = buildString {
        append(timeFormatter.format(entry.date))
        append(" [").append(entry.level.name).append("] ")
        append("[").append(entry.category.rawValue).append("] ")
        append(entry.message)

        if (includesMetadata && entry.metadata.isNotEmpty()) {
            val pairs = entry.metadata.entries
                .sortedBy { it.key }
                .joinToString(", ") { "${it.key}=${it.value}" }
            append(" {").append(pairs).append("}")
        }

        if (includesSource && entry.file.isNotEmpty()) {
            append(" (").append(entry.fileName).append(":").append(entry.line).append(")")
        }
    }

    private companion object {
        /** Device-local wall clock, but a fixed pattern — readable and consistently sortable. */
        val timeFormatter: DateTimeFormatter =
            DateTimeFormatter.ofPattern("HH:mm:ss.SSS").withZone(ZoneId.systemDefault())
    }
}

/** Turns each entry into single-line JSON (NDJSON) — the raw export format. */
class JsonLogFormatter : LogFormatter {
    override fun format(entry: LogEntry): String = LogEntryCodec.encode(entry)
}

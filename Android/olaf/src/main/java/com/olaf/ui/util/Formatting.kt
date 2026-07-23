package com.olaf.ui.util

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Small display helpers shared by the viewer's screens. */
internal object Formatting {

    private val timeFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("HH:mm:ss.SSS").withZone(ZoneId.systemDefault())

    private val dateTimeFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm:ss").withZone(ZoneId.systemDefault())

    fun time(instant: Instant): String = timeFormatter.format(instant)

    fun dateTime(instant: Instant): String = dateTimeFormatter.format(instant)

    /** Human-readable byte count, e.g. `1.2 KB`. */
    fun byteCount(bytes: Long): String = when {
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> String.format(Locale.US, "%.1f KB", bytes / 1024.0)
        else -> String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024))
    }

    fun duration(millis: Long): String = when {
        millis < 1000 -> "${millis}ms"
        else -> String.format(Locale.US, "%.2fs", millis / 1000.0)
    }

    /**
     * Does the text **look like** JSON? Truncation may have broken otherwise-valid JSON, and for
     * highlighting purposes the opening bracket is enough — no strict parse.
     */
    fun looksLikeJson(text: String): Boolean {
        val trimmed = text.trim()
        return trimmed.startsWith("{") || trimmed.startsWith("[")
    }

    /**
     * Line-based search that **keeps JSON blocks whole**: when a matching line opens an object or
     * array that continues below (`"accounts": [`), the whole block down to its matching close is
     * included — a lone `"accounts": [` line tells the reader nothing. Disjoint blocks are
     * separated with `⋯`. Returns `null` when nothing matches.
     */
    fun searchKeepingJsonBlocks(text: String, query: String): String? {
        val lines = text.split("\n")
        val depthAtStart = IntArray(lines.size)
        val depthAtEnd = IntArray(lines.size)
        var depth = 0
        lines.forEachIndexed { index, line ->
            depthAtStart[index] = depth
            depth += bracketDelta(line)
            depthAtEnd[index] = depth
        }

        val included = BooleanArray(lines.size)
        var anyMatch = false
        lines.forEachIndexed { index, line ->
            if (!line.contains(query, ignoreCase = true)) return@forEachIndexed
            anyMatch = true
            included[index] = true
            // The match opens a block that doesn't close on the same line → take it whole.
            if (depthAtEnd[index] <= depthAtStart[index]) return@forEachIndexed
            var next = index + 1
            while (next < lines.size) {
                included[next] = true
                if (depthAtEnd[next] <= depthAtStart[index]) break
                next++
            }
        }
        if (!anyMatch) return null

        val out = StringBuilder()
        var lastIncluded = -1
        lines.indices.filter { included[it] }.forEach { index ->
            if (lastIncluded >= 0 && index > lastIncluded + 1) out.append("⋯\n")
            out.append(lines[index]).append('\n')
            lastIncluded = index
        }
        return out.toString().trimEnd('\n')
    }

    /** Net `{`/`[` minus `}`/`]` on the line, ignoring brackets inside string literals. */
    private fun bracketDelta(line: String): Int {
        var delta = 0
        var inString = false
        var escaped = false
        for (character in line) {
            if (escaped) {
                escaped = false
                continue
            }
            when {
                character == '\\' && inString -> escaped = true
                character == '"' -> inString = !inString
                !inString && (character == '{' || character == '[') -> delta++
                !inString && (character == '}' || character == ']') -> delta--
            }
        }
        return delta
    }
}

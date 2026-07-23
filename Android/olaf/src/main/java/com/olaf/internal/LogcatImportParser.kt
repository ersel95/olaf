package com.olaf.internal

import com.olaf.LogLevel
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Parses `threadtime`-formatted Logcat lines. Pure, so it is directly testable. */
internal object LogcatImportParser {

    data class Parsed(
        val timestamp: Instant,
        val level: LogLevel,
        val tag: String,
        val message: String
    )

    // 07-23 11:15:35.078  8514  8537 I SomeTag: the message
    private val pattern = Regex(
        """^(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\s+\d+\s+\d+\s+([VDIWEF])\s+([^:]*?)\s*:\s?(.*)$"""
    )

    private val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS")

    fun parse(
        line: String,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault()
    ): Parsed? {
        val match = pattern.find(line) ?: return null
        val (rawTime, rawLevel, tag, message) = match.destructured

        // Logcat omits the year, so it comes from the clock. A line stamped in the future can only
        // mean the buffer crossed a year boundary — step back a year rather than import an entry
        // dated ahead of now.
        val nowLocal = LocalDateTime.ofInstant(now, zone)
        val parsed = runCatching {
            LocalDateTime.parse("${nowLocal.year}-$rawTime", formatter)
        }.getOrNull() ?: return null
        val adjusted = if (parsed.isAfter(nowLocal.plusDays(1))) parsed.minusYears(1) else parsed

        return Parsed(
            timestamp = adjusted.atZone(zone).toInstant(),
            level = levelOf(rawLevel),
            tag = tag.trim(),
            message = message
        )
    }

    private fun levelOf(raw: String): LogLevel = when (raw) {
        "V" -> LogLevel.TRACE
        "D" -> LogLevel.DEBUG
        "I" -> LogLevel.INFO
        "W" -> LogLevel.WARNING
        "E" -> LogLevel.ERROR
        "F" -> LogLevel.CRITICAL
        else -> LogLevel.INFO
    }
}

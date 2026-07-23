package com.olaf

import java.time.Instant
import java.util.UUID

/**
 * A single log entry. [message] and [metadata] are stored **raw**, exactly as they came from the
 * call site — no masking or filtering is ever applied (see the package rules in AGENTS.md).
 */
data class LogEntry(
    val id: String = UUID.randomUUID().toString(),
    val date: Instant,
    val level: LogLevel,
    val category: LogCategory,
    val message: String,
    val metadata: Map<String, String> = emptyMap(),
    val file: String = "",
    val line: Int = 0,
    val function: String = "",
    val thread: String = "",
    /**
     * The app session this entry belongs to (every `Olaf.start()` generates a new identifier).
     * Used to group entries by session in the history view.
     */
    val sessionId: String = ""
) {

    /** Only the file name, for display — the call-site capture may carry a package path. */
    val fileName: String
        get() = file.substringAfterLast('/')
}

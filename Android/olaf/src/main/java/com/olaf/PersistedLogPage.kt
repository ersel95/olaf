package com.olaf

/**
 * The return value of [Olaf.loadPersistedPage]: one page of on-disk history.
 */
data class PersistedLogPage(
    /** The page's entries — **oldest to newest** (the caller prepends them to previous pages). */
    val entries: List<LogEntry>,

    /**
     * The **opaque** cursor to pass to the next call for older entries.
     * `null` → the end of history has been reached.
     */
    val nextCursor: String?
)

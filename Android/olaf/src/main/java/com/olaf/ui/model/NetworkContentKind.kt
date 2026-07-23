package com.olaf.ui.model

import com.olaf.LogCategory
import com.olaf.LogEntry

/**
 * Coarse content class derived from the response's `Content-Type`, used by the viewer's
 * "Content type" filter.
 */
enum class NetworkContentKind(val title: String) {
    JSON("JSON"),
    XML("XML"),
    HTML("HTML"),
    IMAGE("Image"),
    TEXT("Text"),
    OTHER("Other");

    companion object {
        /**
         * The record's content class, or `null` when it isn't a network record. Counts as [OTHER]
         * when the response headers weren't captured or carry no `Content-Type`.
         */
        fun of(entry: LogEntry): NetworkContentKind? {
            if (entry.category != LogCategory.Network) return null
            val contentType = entry.metadata.entries
                .firstOrNull { it.key.equals("respH.Content-Type", ignoreCase = true) }
                ?.value
                ?.lowercase()
                ?: return OTHER

            return when {
                contentType.contains("json") -> JSON
                contentType.contains("image/") -> IMAGE
                contentType.contains("html") -> HTML
                contentType.contains("xml") -> XML
                contentType.contains("text/") -> TEXT
                else -> OTHER
            }
        }
    }
}

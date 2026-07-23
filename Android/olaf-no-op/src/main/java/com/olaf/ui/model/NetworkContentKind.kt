package com.olaf.ui.model

import com.olaf.LogEntry

/** No-op stand-in. */
enum class NetworkContentKind(val title: String) {
    JSON("JSON"),
    XML("XML"),
    HTML("HTML"),
    IMAGE("Image"),
    TEXT("Text"),
    OTHER("Other");

    companion object {
        fun of(entry: LogEntry): NetworkContentKind? = null
    }
}

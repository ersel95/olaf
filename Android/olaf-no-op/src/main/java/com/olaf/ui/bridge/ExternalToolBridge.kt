package com.olaf.ui.bridge

import android.content.Context

/** No-op stand-in — a registered bridge is never surfaced, because there is no viewer. */
interface ExternalToolBridge {
    val title: String
    fun open(context: Context)
}

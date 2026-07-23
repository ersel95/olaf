package com.olaf.ui.bridge

import android.content.Context

/**
 * Lets the host surface its own diagnostics tool inside the Olaf viewer as a button. Olaf itself
 * is deliberately **not tied to any external tool** — the host writes the bridge and registers it
 * through `OlafUI.register`.
 *
 * ```kotlin
 * OlafUI.register(object : ExternalToolBridge {
 *     override val title = "SomeTool"
 *     override fun open(context: Context) { SomeTool.show(context) }
 * })
 * ```
 */
interface ExternalToolBridge {
    /** Button label shown in the viewer. */
    val title: String

    /** Invoked when the button is tapped. */
    fun open(context: Context)
}

/** Process-wide registry of external tool bridges. */
internal object ExternalToolRegistry {

    private val bridges = mutableListOf<ExternalToolBridge>()

    fun register(bridge: ExternalToolBridge) {
        synchronized(bridges) {
            if (bridges.none { it.title == bridge.title }) bridges.add(bridge)
        }
    }

    fun removeAll() {
        synchronized(bridges) { bridges.clear() }
    }

    fun all(): List<ExternalToolBridge> = synchronized(bridges) { bridges.toList() }
}

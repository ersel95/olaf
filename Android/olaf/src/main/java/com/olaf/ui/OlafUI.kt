package com.olaf.ui

import android.app.Application
import android.content.Context
import androidx.compose.runtime.Composable
import com.olaf.ui.bridge.ExternalToolBridge
import com.olaf.ui.bridge.ExternalToolRegistry
import com.olaf.ui.presentation.OlafPresenter
import com.olaf.ui.view.OlafViewerScreen

/**
 * The viewer as a plain composable, for hosts that would rather embed it — in a developer-settings
 * screen, say — than have it presented as its own activity.
 *
 * [OlafUI.install] and [OlafUI.present] remain the usual path; this is the escape hatch when the
 * viewer needs to live inside an existing navigation graph.
 */
@Composable
fun OlafViewer(onClose: () -> Unit = {}) {
    OlafViewerScreen(onClose = onClose)
}

/**
 * Facade for the viewer: shake-to-open setup, external tool registration and programmatic
 * presentation.
 *
 * ```kotlin
 * Olaf.start(context)
 * OlafUI.install(application)   // shake → viewer
 * ```
 */
object OlafUI {

    /**
     * Installs the shake observer that opens the viewer, and registers the given external tools.
     * Idempotent; call once, typically from `Application.onCreate`.
     */
    fun install(application: Application, tools: List<ExternalToolBridge> = emptyList()) {
        OlafPresenter.install(application)
        tools.forEach(ExternalToolRegistry::register)
    }

    /** Registers a single external tool bridge; it becomes a button in the viewer. */
    fun register(bridge: ExternalToolBridge) {
        ExternalToolRegistry.register(bridge)
    }

    /** Removes every registered external tool. */
    fun unregisterAllTools() {
        ExternalToolRegistry.removeAll()
    }

    /**
     * Registers a handler for taps on the Olaf title in the viewer's app bar.
     *
     * With a handler set, the title becomes a button: tapping it closes the viewer and invokes the
     * handler, which makes it safe to present another diagnostics tool from there. Useful when
     * Olaf is installed alongside a second shake-activated tool — the shake opens Olaf, and the
     * title hands off. Pass `null` to remove the handler.
     */
    fun onLogoTap(handler: (() -> Unit)?) {
        OlafPresenter.logoTapHandler = handler
    }

    /** Opens the viewer programmatically. */
    fun present(context: Context? = null) {
        OlafPresenter.present(context)
    }

    /** Closes the viewer programmatically. */
    fun dismiss() {
        OlafPresenter.dismiss()
    }
}

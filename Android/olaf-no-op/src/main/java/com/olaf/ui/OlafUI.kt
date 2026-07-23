package com.olaf.ui

import android.app.Application
import android.content.Context
import androidx.compose.runtime.Composable
import com.olaf.ui.bridge.ExternalToolBridge

/*
 * No-op counterpart of the viewer facade: no shake observer is installed and no activity exists,
 * so nothing of the viewer ends up in the release APK.
 */

/** No-op stand-in — renders nothing, so an embedded viewer simply disappears in release. */
@Composable
fun OlafViewer(onClose: () -> Unit = {}) = Unit

/** No-op stand-in. */
object OlafUI {

    fun install(application: Application, tools: List<ExternalToolBridge> = emptyList()) = Unit

    fun register(bridge: ExternalToolBridge) = Unit

    fun unregisterAllTools() = Unit

    fun onLogoTap(handler: (() -> Unit)?) = Unit

    fun present(context: Context? = null) = Unit

    fun dismiss() = Unit
}

package com.olaf.ui.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.olaf.ui.view.OlafTheme
import com.olaf.ui.view.OlafViewerScreen

/**
 * Hosts the viewer. Kept separate from the host app's activities so opening Olaf never disturbs
 * the app's navigation state — the Android counterpart of iOS's dedicated viewer window.
 */
internal class OlafViewerActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge-to-edge is the platform default from Android 15 on; opting in here means the
        // viewer draws behind the system bars and the scaffolds inset their own content.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        OlafPresenter.onViewerCreated(this)

        setContent {
            OlafTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    OlafViewerScreen(onClose = { finish() })
                }
            }
        }
    }

    override fun onDestroy() {
        OlafPresenter.onViewerDestroyed()
        super.onDestroy()
    }
}

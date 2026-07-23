package com.olaf.ui.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxSize
import com.olaf.ui.view.OlafViewerScreen

/**
 * Hosts the viewer. Kept separate from the host app's activities so opening Olaf never disturbs
 * the app's navigation state — the Android counterpart of iOS's dedicated viewer window.
 */
internal class OlafViewerActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        OlafPresenter.onViewerCreated(this)

        setContent {
            // The viewer carries its own Material theme rather than inheriting the host's, so it
            // looks and reads the same in every app it is embedded in.
            MaterialTheme(
                colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()
            ) {
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

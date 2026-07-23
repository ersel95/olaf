package com.olaf.ui.view

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

/**
 * The viewer's theme.
 *
 * On Android 12+ it follows the device's dynamic colour, so Olaf looks like it belongs to the
 * phone it is running on rather than to whichever app embedded it — the platform-native answer to
 * "does this feel like an Android tool". Older releases fall back to the Material baseline.
 *
 * Semantic colours (status pills, level dots) stay fixed on purpose: a 500 has to read as a
 * failure whatever the wallpaper is.
 */
@Composable
internal fun OlafTheme(content: @Composable () -> Unit) {
    val darkTheme = isSystemInDarkTheme()
    val context = LocalContext.current

    val colorScheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)

        darkTheme -> darkColorScheme()
        else -> lightColorScheme()
    }

    MaterialTheme(colorScheme = colorScheme, content = content)
}

package com.olaf.ui.view

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import com.olaf.LogLevel

/**
 * Colours used to tell levels and status codes apart. They are fixed rather than theme-derived, so
 * a record reads the same regardless of the host app's palette — and they mirror the iOS viewer.
 */
internal object OlafColors {
    val Gray = Color(0xFF8E8E93)
    val Blue = Color(0xFF0A84FF)
    val Teal = Color(0xFF30B0C7)
    val Orange = Color(0xFFFF9500)
    val Red = Color(0xFFFF3B30)
    val Pink = Color(0xFFFF2D55)
    val Green = Color(0xFF34C759)
}

@Composable
@ReadOnlyComposable
internal fun LogLevel.color(): Color = when (this) {
    LogLevel.TRACE -> OlafColors.Gray
    LogLevel.DEBUG -> OlafColors.Gray
    LogLevel.INFO -> OlafColors.Blue
    LogLevel.NOTICE -> OlafColors.Teal
    LogLevel.WARNING -> OlafColors.Orange
    LogLevel.ERROR -> OlafColors.Red
    LogLevel.CRITICAL -> OlafColors.Pink
}

/** Colour of the status pill: green 2xx, teal 3xx, orange 4xx, red 5xx and failures. */
internal fun statusColor(statusCode: Int?, isFailure: Boolean): Color = when {
    isFailure -> OlafColors.Red
    statusCode == null -> OlafColors.Gray
    statusCode in 200..299 -> OlafColors.Green
    statusCode in 300..399 -> OlafColors.Teal
    statusCode in 400..499 -> OlafColors.Orange
    else -> OlafColors.Red
}

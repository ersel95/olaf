package com.olaf.ui.view

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.olaf.LogLevel

/** Coloured pill carrying the HTTP status code, or the failure marker. */
@Composable
internal fun StatusPill(statusCode: Int?, isFailure: Boolean, modifier: Modifier = Modifier) {
    val text = statusCode?.toString() ?: if (isFailure) "ERR" else "•••"
    Text(
        text = text,
        color = Color.White,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.Monospace,
        style = MaterialTheme.typography.labelSmall,
        modifier = modifier
            .background(statusColor(statusCode, isFailure), RoundedCornerShape(6.dp))
            .padding(horizontal = 7.dp, vertical = 3.dp)
    )
}

/** HTTP method badge. */
@Composable
internal fun MethodBadge(method: String, modifier: Modifier = Modifier) {
    Text(
        text = method.uppercase(),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontWeight = FontWeight.SemiBold,
        fontFamily = FontFamily.Monospace,
        style = MaterialTheme.typography.labelSmall,
        modifier = modifier
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(4.dp))
            .padding(horizontal = 5.dp, vertical = 2.dp)
    )
}

/** Marks a mocked response, so a canned reply is never mistaken for a real one. */
@Composable
internal fun MockBadge(modifier: Modifier = Modifier) {
    Text(
        text = "MOCK",
        color = Color.White,
        fontWeight = FontWeight.Bold,
        style = MaterialTheme.typography.labelSmall,
        modifier = modifier
            .background(OlafColors.Teal, RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 1.dp)
    )
}

/** The level dot shown at the leading edge of a plain log row. */
@Composable
internal fun LevelDot(level: LogLevel, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(8.dp)
            .background(level.color(), CircleShape)
    )
}

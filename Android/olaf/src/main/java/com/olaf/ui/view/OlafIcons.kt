package com.olaf.ui.view

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/**
 * The icons the viewer uses.
 *
 * Only `material-icons-core` is pulled in — `material-icons-extended` would add megabytes for a
 * handful of glyphs — so the two symbols missing from core (a filter funnel and a pin) are drawn
 * here from the same Material geometry, rather than substituted with something that reads wrong.
 */
internal object OlafIcons {
    val Back: ImageVector get() = Icons.AutoMirrored.Filled.ArrowBack
    val More: ImageVector get() = Icons.Filled.MoreVert
    val Share: ImageVector get() = Icons.Filled.Share
    val Search: ImageVector get() = Icons.Filled.Search
    val Clear: ImageVector get() = Icons.Filled.Close
    val Filter: ImageVector get() = filterIcon
    val Pin: ImageVector get() = pinIcon

    private val filterIcon: ImageVector by lazy {
        materialIcon("Filter") {
            // Material's `filter_list`: three centred bars of decreasing width.
            path(fill = SolidColor(Color.Black)) {
                moveTo(10f, 18f); horizontalLineToRelative(4f); verticalLineToRelative(-2f)
                horizontalLineToRelative(-4f); close()
                moveTo(3f, 6f); verticalLineToRelative(2f); horizontalLineToRelative(18f)
                verticalLineTo(6f); close()
                moveTo(6f, 13f); horizontalLineToRelative(12f); verticalLineToRelative(-2f)
                horizontalLineTo(6f); close()
            }
        }
    }

    private val pinIcon: ImageVector by lazy {
        materialIcon("Pin") {
            // Material's `push_pin`.
            path(fill = SolidColor(Color.Black)) {
                moveTo(16f, 9f); verticalLineTo(4f); horizontalLineToRelative(1f)
                verticalLineTo(2f); horizontalLineTo(7f); verticalLineToRelative(2f)
                horizontalLineToRelative(1f); verticalLineToRelative(5f)
                curveToRelative(0f, 1.66f, -1.34f, 3f, -3f, 3f); verticalLineToRelative(2f)
                horizontalLineToRelative(5.97f); verticalLineToRelative(7f)
                lineToRelative(1f, 1f); lineToRelative(1f, -1f); verticalLineToRelative(-7f)
                horizontalLineTo(19f); verticalLineToRelative(-2f)
                curveToRelative(-1.66f, 0f, -3f, -1.34f, -3f, -3f); close()
            }
        }
    }

    private fun materialIcon(
        name: String,
        block: ImageVector.Builder.() -> ImageVector.Builder
    ): ImageVector = ImageVector.Builder(
        name = name,
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f
    ).block().build()
}

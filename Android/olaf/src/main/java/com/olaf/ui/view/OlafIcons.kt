package com.olaf.ui.view

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * The icons the viewer uses, resolved in one place. Only `material-icons-core` is pulled in —
 * `material-icons-extended` would add megabytes for a handful of glyphs.
 */
internal object OlafIcons {
    val Back: ImageVector get() = Icons.AutoMirrored.Filled.ArrowBack
    val More: ImageVector get() = Icons.Filled.MoreVert
    val Filter: ImageVector get() = Icons.AutoMirrored.Filled.List
    val Pin: ImageVector get() = Icons.Filled.Star
    val Share: ImageVector get() = Icons.Filled.Share
}

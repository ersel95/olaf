package com.olaf.ui.util

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

/**
 * Hands a file to the system share sheet — the Android counterpart of iOS's share sheet.
 *
 * The URI is produced by Olaf's own [FileProvider] (declared in the library manifest, with an
 * authority derived from the host's package name), so the host doesn't need to configure
 * anything. Nothing is ever shared without an explicit user action.
 */
internal fun shareFile(context: Context, file: File, mimeType: String = "text/plain") {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.olaf.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mimeType
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share logs").apply {
        if (context !is android.app.Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    })
}

/** Copies text to the clipboard. */
internal fun copyToClipboard(context: Context, label: String, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
    clipboard?.setPrimaryClip(android.content.ClipData.newPlainText(label, text))
}

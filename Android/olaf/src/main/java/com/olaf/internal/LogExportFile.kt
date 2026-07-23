package com.olaf.internal

import java.io.File

/**
 * Writes logs to a shareable file under the app's cache directory.
 *
 * Both the full-history export and the viewer's **filtered** export go through here, which keeps
 * cleanup and file naming in one place. The directory sits inside `cacheDir` so it can be handed
 * to a `FileProvider` without extra permissions.
 */
internal object LogExportFile {

    const val PREFIX = "olaf-export-"
    const val DIRECTORY_NAME = "olaf-exports"

    /**
     * Writes [text] into a shareable file (`.log` or `.ndjson`), first purging previous exports so
     * sensitive logs don't pile up in the cache. Returns `null` if the write fails.
     */
    fun write(
        cacheDirectory: File,
        text: String,
        fileExtension: String = "log",
        nowMillis: Long = System.currentTimeMillis()
    ): File? = try {
        val directory = File(cacheDirectory, DIRECTORY_NAME)
        directory.mkdirs()
        purgeOld(cacheDirectory)
        val file = File(directory, "$PREFIX${nowMillis / 1000}.$fileExtension")
        file.writeText(text)
        file
    } catch (_: Throwable) {
        null
    }

    /** Deletes previously written `olaf-export-*` files. */
    fun purgeOld(cacheDirectory: File) {
        val directory = File(cacheDirectory, DIRECTORY_NAME)
        directory.listFiles()?.forEach { file ->
            if (file.name.startsWith(PREFIX)) file.delete()
        }
    }
}

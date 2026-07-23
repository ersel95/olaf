package com.olaf.ui.util

import com.olaf.ui.model.NetworkLogInfo

/**
 * Renders a captured request as a cURL command.
 *
 * Header and body values are **raw** — secrets such as `Authorization` and `Cookie` pass through
 * verbatim, which is exactly what makes the output useful and exactly why it must be reviewed
 * before being shared.
 */
internal object CurlBuilder {

    fun curl(info: NetworkLogInfo): String {
        val parts = mutableListOf("curl -X ${info.method ?: "GET"} ${quote(info.url.orEmpty())}")
        info.requestHeaders.forEach { (key, value) ->
            parts.add("-H ${quote("$key: $value")}")
        }
        info.requestBody?.takeIf { it.isNotEmpty() }?.let { parts.add("-d ${quote(it)}") }
        return parts.joinToString(" \\\n  ")
    }

    /** Single-quoted shell argument, with embedded single quotes escaped safely. */
    private fun quote(value: String): String = "'" + value.replace("'", "'\\''") + "'"
}

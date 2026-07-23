package com.olaf

/**
 * Extracts a readable field path plus description from a deserialization failure.
 *
 * Gson and Moshi both append the failing path to their message (`… at path $.user.accounts[0].iban`),
 * which is the closest Android equivalent of the coding path iOS reads off `DecodingError`.
 * Anything else falls back to the plain message.
 */
internal object DecodingErrorDescriber {

    data class Described(val path: String?, val detail: String)

    private val pathPattern = Regex("""(?:at )?path (\$[^\s]*)""")

    fun describe(error: Throwable): Described {
        val detail = error.message ?: error.javaClass.simpleName
        val path = pathPattern.find(detail)?.groupValues?.getOrNull(1)
        return Described(path = path, detail = detail)
    }

    const val MAX_BODY_CHARS = 8000
}

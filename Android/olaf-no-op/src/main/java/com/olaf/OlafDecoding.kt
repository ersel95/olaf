package com.olaf

/**
 * No-op stand-in. The block still runs and its errors still propagate — only the logging is gone,
 * so wrapping a parse in release changes nothing about its behaviour.
 */
object OlafDecoding {

    inline fun <T> decode(
        url: String? = null,
        body: String? = null,
        typeName: String? = null,
        category: LogCategory = LogCategory.Decoding,
        block: () -> T
    ): T = block()
}

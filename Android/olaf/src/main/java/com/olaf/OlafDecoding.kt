package com.olaf

/**
 * Wrapper that logs a failed deserialization and rethrows the error **untouched**.
 *
 * The counterpart of iOS's `OlafDecoding.decode`, but parser-agnostic: because it takes a lambda
 * rather than a decoder, it works with Gson, Moshi, kotlinx.serialization or anything else —
 * without Olaf depending on any of them.
 *
 * ```kotlin
 * val user = OlafDecoding.decode(url = response.request.url.toString(), body = body, typeName = "User") {
 *     gson.fromJson(body, User::class.java)
 * }
 * ```
 */
object OlafDecoding {

    inline fun <T> decode(
        url: String? = null,
        body: String? = null,
        typeName: String? = null,
        category: LogCategory = LogCategory.Decoding,
        block: () -> T
    ): T = try {
        block()
    } catch (error: Throwable) {
        Olaf.logDecodingError(error, url = url, body = body, typeName = typeName, category = category)
        throw error
    }
}

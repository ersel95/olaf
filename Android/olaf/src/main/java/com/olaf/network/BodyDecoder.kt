package com.olaf.network

/**
 * Turns a body Olaf can't read on its own into something readable — Protobuf, MessagePack, an
 * encrypted payload, anything.
 *
 * Decoders are tried in order and the first non-null result wins; returning `null` passes the body
 * to the next one, and finally to the built-in text handling. They run on the calling thread as
 * part of capture, so they should be cheap and must not throw — a decoder that fails is skipped
 * rather than breaking the request.
 *
 * ```kotlin
 * OlafNetwork.configuration = OlafNetworkConfiguration(
 *     bodyDecoders = listOf(
 *         BodyDecoder { bytes, contentType, _ ->
 *             if (contentType?.contains("protobuf") == true) MyProto.parseFrom(bytes).toString() else null
 *         }
 *     )
 * )
 * ```
 *
 * ### Compressed bodies
 * Gzip needs no decoder: OkHttp transparently decompresses it before an application interceptor
 * sees the body. Brotli does too, as long as OkHttp's own `BrotliInterceptor` is installed
 * **after** Olaf's, so that Olaf — sitting further out in the chain — observes the decompressed
 * body:
 *
 * ```kotlin
 * OkHttpClient.Builder()
 *     .addInterceptor(OlafNetwork.interceptor())   // outer: sees the decoded body
 *     .addInterceptor(BrotliInterceptor)           // inner: does the decoding
 * ```
 */
fun interface BodyDecoder {

    /**
     * @param bytes the raw body as captured.
     * @param contentType the `Content-Type` header, if any.
     * @param contentEncoding the `Content-Encoding` header, if any.
     * @return the readable representation, or `null` to let the next decoder try.
     */
    fun decode(bytes: ByteArray, contentType: String?, contentEncoding: String?): String?
}

package com.olaf.network

import com.olaf.Olaf
import okhttp3.Interceptor
import okhttp3.Response
import okio.Buffer
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.Base64
import java.util.concurrent.TimeUnit

/**
 * OkHttp interceptor that captures requests/responses and logs them to Olaf **raw** (unredacted)
 * under the configured category.
 *
 * This is the Android counterpart of the iOS package's `URLProtocol` capture. Because an
 * interceptor already sits inside the call chain, there is no proxy session to re-issue the
 * request through — which also means the host's TLS configuration, certificate pinning and
 * timeouts apply untouched.
 *
 * Install it as an **application** interceptor, so bodies are seen decompressed and redirects are
 * captured as a single logical call:
 *
 * ```kotlin
 * OkHttpClient.Builder().addInterceptor(OlafNetwork.interceptor())
 * ```
 */
internal class OlafInterceptor : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val config = OlafNetwork.configuration
        val url = request.url.toString()

        // Mocks take priority over the capture filters, exactly as on iOS.
        val mock = OlafNetwork.mock(request)
        if (mock == null && !config.shouldCapture(url)) {
            return chain.proceed(request)
        }

        val method = request.method
        val pendingId = PendingRequestRegistry.register(method, url)
        val startNanos = System.nanoTime()

        val requestBodyBytes = request.body?.contentLength()?.takeIf { it >= 0 } ?: 0
        val requestBodyText = if (config.capturesBodies) readRequestBody(chain) else null
        val requestHeaders = if (config.capturesHeaders) request.headers.toMap() else null

        if (mock != null) {
            return deliverMock(chain, mock, pendingId, startNanos, requestBodyText, requestBodyBytes, requestHeaders)
        }

        val response = try {
            chain.proceed(request)
        } catch (failure: IOException) {
            PendingRequestRegistry.unregister(pendingId)
            val cancelled = chain.call().isCanceled()
            log(
                NetworkLogEvent(
                    method = method,
                    url = url,
                    durationMs = elapsedMs(startNanos),
                    requestBytes = requestBodyBytes,
                    error = if (cancelled) null else (failure.message ?: failure.javaClass.simpleName),
                    cancelled = cancelled,
                    requestBody = requestBodyText,
                    requestHeaders = requestHeaders,
                    timing = OlafEventListener.TimingRegistry.take(chain.call())
                )
            )
            throw failure
        }

        PendingRequestRegistry.unregister(pendingId)

        val body = response.body
        val contentType = body.contentType()
        val charset = contentType?.charset(Charsets.UTF_8) ?: Charsets.UTF_8

        // Peeking the source buffers the payload without consuming it, so the caller still reads
        // the body normally. When body capture is off we never touch the stream at all.
        val responseBytes: Long
        var responseBodyText: String? = null
        var responseImageBase64: String? = null

        if (config.capturesBodies) {
            val source = body.source()
            source.request(Long.MAX_VALUE)
            val buffer = source.buffer
            responseBytes = buffer.size

            val isImage = contentType?.type.equals("image", ignoreCase = true)
            if (isImage) {
                if (config.maxImageBodyBytes > 0 && buffer.size <= config.maxImageBodyBytes) {
                    responseImageBase64 = Base64.getEncoder().encodeToString(buffer.clone().readByteArray())
                }
                responseBodyText = "<${buffer.size} bytes ${contentType}>"
            } else {
                responseBodyText = decodeBody(
                    bytes = { buffer.clone().readByteArray() },
                    text = { buffer.clone().readString(charset) },
                    contentType = contentType?.toString(),
                    contentEncoding = response.header("Content-Encoding"),
                    config = config
                )
            }
        } else {
            responseBytes = body.contentLength().takeIf { it >= 0 } ?: 0
        }

        log(
            NetworkLogEvent(
                method = method,
                url = url,
                statusCode = response.code,
                durationMs = elapsedMs(startNanos),
                requestBytes = requestBodyBytes,
                responseBytes = responseBytes,
                requestBody = requestBodyText,
                responseBody = responseBodyText,
                requestHeaders = requestHeaders,
                responseHeaders = if (config.capturesHeaders) response.headers.toMap() else null,
                timing = OlafEventListener.TimingRegistry.take(chain.call()),
                responseImageBase64 = responseImageBase64
            )
        )

        return response
    }

    // MARK: - Mock delivery

    private fun deliverMock(
        chain: Interceptor.Chain,
        mock: OlafMockResponse,
        pendingId: String,
        startNanos: Long,
        requestBodyText: String?,
        requestBodyBytes: Long,
        requestHeaders: Map<String, String>?
    ): Response {
        val request = chain.request()
        val config = OlafNetwork.configuration

        if (mock.delayMillis > 0) {
            try {
                TimeUnit.MILLISECONDS.sleep(mock.delayMillis)
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
                PendingRequestRegistry.unregister(pendingId)
                throw IOException("Olaf mock delay interrupted", interrupted)
            }
        }

        PendingRequestRegistry.unregister(pendingId)

        val transportError = mock.transportError
        if (transportError != null) {
            log(
                NetworkLogEvent(
                    method = request.method,
                    url = request.url.toString(),
                    durationMs = elapsedMs(startNanos),
                    requestBytes = requestBodyBytes,
                    error = transportError.message,
                    requestBody = requestBodyText,
                    requestHeaders = requestHeaders,
                    mocked = true
                )
            )
            throw transportError.toIOException()
        }

        val response = mock.toResponse(request)
        log(
            NetworkLogEvent(
                method = request.method,
                url = request.url.toString(),
                statusCode = mock.statusCode,
                durationMs = elapsedMs(startNanos),
                requestBytes = requestBodyBytes,
                responseBytes = mock.body.size.toLong(),
                requestBody = requestBodyText,
                responseBody = if (config.capturesBodies) {
                    prettyBody(String(mock.body, Charsets.UTF_8), config.maxBodyLength)
                } else {
                    null
                },
                requestHeaders = requestHeaders,
                responseHeaders = if (config.capturesHeaders) mock.headers else null,
                mocked = true
            )
        )
        return response
    }

    // MARK: - Helpers

    private fun log(event: NetworkLogEvent) {
        Olaf.log(
            level = NetworkLogComposer.level(event.statusCode, event.error, event.cancelled),
            message = NetworkLogComposer.message(event),
            category = OlafNetwork.configuration.category,
            metadata = NetworkLogComposer.metadata(event)
        )
    }

    private fun elapsedMs(startNanos: Long): Long = (System.nanoTime() - startNanos) / 1_000_000

    private fun readRequestBody(chain: Interceptor.Chain): String? {
        val body = chain.request().body ?: return null
        // One-shot and duplex bodies can only be written once — reading them here would starve
        // the actual request, so they are deliberately left uncaptured.
        if (body.isOneShot() || body.isDuplex()) return null
        return try {
            val buffer = Buffer()
            body.writeTo(buffer)
            val charset = body.contentType()?.charset(Charsets.UTF_8) ?: Charsets.UTF_8
            decodeBody(
                bytes = { buffer.clone().readByteArray() },
                text = { buffer.clone().readString(charset) },
                contentType = body.contentType()?.toString(),
                contentEncoding = chain.request().header("Content-Encoding"),
                config = OlafNetwork.configuration
            )
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Runs the configured [BodyDecoder]s before falling back to plain text. The body is only
     * materialised as a ByteArray when a decoder actually exists, so the common path stays on the
     * cheaper string route.
     */
    private fun decodeBody(
        bytes: () -> ByteArray,
        text: () -> String,
        contentType: String?,
        contentEncoding: String?,
        config: OlafNetworkConfiguration
    ): String? {
        if (config.bodyDecoders.isNotEmpty()) {
            val raw = bytes()
            for (decoder in config.bodyDecoders) {
                // A misbehaving decoder must never take the request down with it.
                val decoded = runCatching { decoder.decode(raw, contentType, contentEncoding) }.getOrNull()
                if (decoded != null) return prettyBody(decoded, config.maxBodyLength)
            }
        }
        return prettyBody(text(), config.maxBodyLength)
    }

    private fun prettyBody(raw: String, limit: Int): String? {
        if (raw.isEmpty() || limit <= 0) return null
        // JSON is pretty-printed at capture time, so the viewer renders it indented (and the
        // syntax highlighter has something to work with) without re-parsing on every draw.
        val pretty = prettyJson(raw) ?: raw
        return if (pretty.length > limit) pretty.take(limit) + "…" else pretty
    }

    private fun prettyJson(raw: String): String? {
        val trimmed = raw.trim()
        return try {
            when {
                trimmed.startsWith("{") -> JSONObject(trimmed).toString(2)
                trimmed.startsWith("[") -> JSONArray(trimmed).toString(2)
                else -> null
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun okhttp3.Headers.toMap(): Map<String, String> =
        (0 until size).associate { index -> name(index) to value(index) }
}

import Foundation
import OlafCore

/// İstek/yanıtları yakalayıp Olaf'a loglayan `URLProtocol`. Gerçek isteği kendi (yakalanmayan)
/// session'ı üzerinden yürütür ve sonucu istemciye iletir.
final class OlafURLProtocol: URLProtocol {

    private static let handledKey = "com.olaf.network.handled"

    private var proxySession: URLSession?
    private var proxyTask: URLSessionDataTask?
    /// Yalnız gövde yakalama açıkken (`capturesBodies`) doldurulur; kapalıyken büyük indirmeleri
    /// gereksiz yere RAM'de tutmamak için boş kalır (sayım `responseByteCount`'tan gelir).
    private var responseData = Data()
    private var responseByteCount = 0
    private var capturesBodies = true
    private var capturedResponse: URLResponse?
    /// İstek gövdesi: `URLSession` `httpBody`'yi `httpBodyStream`'e çevirdiğinden protokolde
    /// `request.httpBody` çoğu zaman `nil`'dir; gövde `startLoading`'de buraya yakalanır.
    private var capturedRequestBody: Data?
    private var startDate = Date()

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        // Sonsuz döngüyü önle: bizim başlattığımız isteği tekrar yakalama.
        if URLProtocol.property(forKey: handledKey, in: request) != nil { return false }
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        // baseURL allow/deny filtresi: filtre dışı istekler yakalanmaz (olduğu gibi geçer).
        return OlafNetwork.current.shouldCapture(request.url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        startDate = Date()
        capturesBodies = OlafNetwork.current.capturesBodies

        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)

        // İstek gövdesini yakala. `URLSession`, `httpBody`'yi protokol görmeden `httpBodyStream`'e
        // çevirdiği için çoğu POST/PUT'ta `httpBody == nil`'dir. Stream'i burada boşaltıp hem yakalar
        // hem de proxy isteğine `httpBody` olarak geri koyarız (stream tek sefer okunur; geri koymazsak
        // gövde sunucuya gitmez). Yalnız gövde yakalama açıkken yapılır; kapalıyken stream'e dokunmayız.
        if capturesBodies {
            if let body = request.httpBody {
                capturedRequestBody = body
            } else if let stream = request.httpBodyStream {
                let drained = Self.drainStream(stream)
                if !drained.isEmpty {
                    capturedRequestBody = drained
                    mutable.httpBody = drained
                }
            }
        }

        // Proxy session: capture'a özel, izole (shared cookie/cache havuzunu kullanmasın).
        let config = URLSessionConfiguration.ephemeral
        // Zincirlenen protokoller (başka capture araçları) proxy session'da yakalasın diye eklenir.
        // OlafURLProtocol bu listeye girmez (sonsuz döngüyü handledKey + dışlama önler).
        let selfID = ObjectIdentifier(OlafURLProtocol.self)
        let chained = OlafNetwork.chainedProtocolClasses.filter { ObjectIdentifier($0) != selfID }
        if !chained.isEmpty {
            config.protocolClasses = chained + (config.protocolClasses ?? [])
        }
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.proxySession = session
        self.proxyTask = session.dataTask(with: mutable as URLRequest)
        self.proxyTask?.resume()
    }

    override func stopLoading() {
        proxyTask?.cancel()
        proxySession?.invalidateAndCancel()
        proxySession = nil
    }

    // MARK: - Loglama

    private func logCompletion(error: Error?) {
        let config = OlafNetwork.current
        let http = capturedResponse as? HTTPURLResponse
        let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)

        var event = NetworkLogEvent(
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "-",
            statusCode: http?.statusCode,
            durationMs: durationMs,
            requestBytes: capturedRequestBody?.count ?? request.httpBody?.count ?? 0,
            responseBytes: responseByteCount,
            error: error.map { ($0 as NSError).localizedDescription },
            requestBody: nil,
            responseBody: nil
        )

        if config.capturesBodies {
            event.requestBody = bodyString(from: capturedRequestBody ?? request.httpBody, limit: config.maxBodyLength)
            event.responseBody = bodyString(from: responseData, limit: config.maxBodyLength)
        }

        if config.capturesHeaders {
            event.requestHeaders = request.allHTTPHeaderFields
            event.responseHeaders = (http?.allHeaderFields as? [String: String])
        }

        Olaf.log(
            NetworkLogComposer.level(statusCode: event.statusCode, error: event.error),
            NetworkLogComposer.message(for: event),
            category: config.category,
            metadata: NetworkLogComposer.metadata(for: event)
        )
    }

    private func bodyString(from data: Data?, limit: Int) -> String? {
        guard let data, !data.isEmpty, limit > 0 else { return nil }
        // JSON ise yakalama anında pretty-print ederek sakla → viewer'da girintili görünür.
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text.count > limit ? String(text.prefix(limit)) + "…" : text
        }
        guard let text = String(data: data, encoding: .utf8) else { return "<\(data.count) bytes binary>" }
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// `httpBodyStream`'i tamamen okuyup `Data`'ya çevirir. Stream tek sefer okunabildiğinden,
    /// dönen veri proxy isteğine `httpBody` olarak geri konmalıdır (yoksa gövde sunucuya gitmez).
    private static func drainStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 8192
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break } // 0 = bitti, <0 = hata
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - URLSessionDataDelegate (yakalama + istemciye iletim)

extension OlafURLProtocol: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        capturedResponse = response
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseByteCount += data.count
        // Gövde yakalama kapalıysa veriyi biriktirme (yalnız byte say) → büyük indirmelerde RAM tasarrufu.
        if capturesBodies { responseData.append(data) }
        client?.urlProtocol(self, didLoad: data)
    }

    /// Sunucu trust challenge'ı. **Varsayılan**: sistem doğrulaması (`.performDefaultHandling`) →
    /// proxy session host'un cert pinning'ini/OS trust zincirini ezmez; geçersiz/pinlenmemiş sertifika
    /// reddedilir (eski `URLCredential(trust:)` baypası kaldırıldı).
    ///
    /// **Opt-in (yalnız non-prod)**: `allowsArbitraryServerTrustForCapture == true` ise server-trust
    /// challenge'ında sunucunun sunduğu trust koşulsuz kabul edilir. Host kendi özel CA'sına / iç test
    /// gateway'ine güveniyorsa (capture proxy'si host'un trust delegate'ini PAYLAŞMAZ → default doğrulama
    /// TLS -9807 verir), bu bayrak capture'ın o trafiği geçirmesini sağlar. Olaf zaten `#if !PROD`'da derlenir.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           OlafNetwork.current.allowsArbitraryServerTrustForCapture,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
        logCompletion(error: error)
        proxySession?.finishTasksAndInvalidate()
        proxySession = nil
    }
}

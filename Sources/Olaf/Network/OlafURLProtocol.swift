import Foundation

/// İstek/yanıtları yakalayıp Olaf'a loglayan `URLProtocol`. Gerçek isteği, tüm yakalamaların
/// paylaştığı (yakalanmayan) proxy session (`OlafProxySession`) üzerinden yürütür ve sonucu
/// istemciye iletir.
final class OlafURLProtocol: URLProtocol {

    private static let handledKey = "com.olaf.network.handled"

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
    /// "Aktif istekler" kaydının kimliği; tamamlanınca (başarı/hata/iptal) düşürülür.
    private var pendingID: UUID?
    /// Proxy task'ın zamanlama metrikleri (`didFinishCollecting` — `didComplete`'ten önce gelir).
    private var capturedMetrics: URLSessionTaskMetrics?

    /// `stopLoading` sonrası istemciye çağrı yapılmaz (URL loading sistemi protokolü bıraktı).
    /// `stopLoading` istemci kuyruğundan, proxy callback'leri delegate kuyruğundan gelir → kilit.
    private let stateLock = NSLock()
    private var _stopped = false
    private var isStopped: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _stopped }
        set { stateLock.lock(); _stopped = newValue; stateLock.unlock() }
    }

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

        pendingID = PendingRequestRegistry.shared.register(
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "-"
        )
        proxyTask = OlafProxySession.shared.startTask(with: mutable as URLRequest, handler: self)
    }

    override func stopLoading() {
        isStopped = true
        // Tamamlanmış task'ta cancel no-op'tur; yarıda kesilen task `didCompleteWithError(cancelled)`
        // üretir → `.info` seviyesinde "iptal" olarak loglanır (handler orada düşürülür).
        proxyTask?.cancel()
        proxyTask = nil
    }

    // MARK: - Proxy callback'leri (OlafProxySession delegate kuyruğundan yönlendirilir)

    func proxyDidReceive(_ response: URLResponse) {
        capturedResponse = response
        guard !isStopped else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func proxyDidReceive(_ data: Data) {
        responseByteCount += data.count
        // Gövde yakalama kapalıysa veriyi biriktirme (yalnız byte say) → büyük indirmelerde RAM tasarrufu.
        if capturesBodies { responseData.append(data) }
        guard !isStopped else { return }
        client?.urlProtocol(self, didLoad: data)
    }

    func proxyWasRedirected(to newRequest: URLRequest, response: HTTPURLResponse) {
        guard !isStopped else { return }
        client?.urlProtocol(self, wasRedirectedTo: newRequest, redirectResponse: response)
    }

    func proxyDidCollect(_ metrics: URLSessionTaskMetrics) {
        capturedMetrics = metrics
    }

    func proxyDidComplete(error: Error?) {
        if let pendingID {
            PendingRequestRegistry.shared.unregister(pendingID)
        }
        if !isStopped {
            if let error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        // Ağır kısım (JSON pretty-print + loglama) paylaşılan delegate kuyruğunu bekletmesin diye
        // Sendable bir anlık görüntüyle ayrı kuyruğa taşınır. Bu noktadan sonra task için başka
        // callback gelmez → alanlar sabittir, kopyalamak güvenlidir.
        let nsError = error as NSError?
        let cancelled = nsError.map { $0.domain == NSURLErrorDomain && $0.code == NSURLErrorCancelled } ?? false

        // Görsel önizleme: image/* yanıtlar sınır altındaysa base64 saklanır (detayda gösterilir).
        var imageBase64: String?
        let responseContentType = (capturedResponse as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?.lowercased()
        let imageLimit = OlafNetwork.current.maxImageBodyBytes
        if capturesBodies,
           let responseContentType, responseContentType.hasPrefix("image/"),
           !responseData.isEmpty, responseData.count <= imageLimit {
            imageBase64 = responseData.base64EncodedString()
        }

        let completion = CaptureCompletion(
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "-",
            statusCode: (capturedResponse as? HTTPURLResponse)?.statusCode,
            durationMs: Int(Date().timeIntervalSince(startDate) * 1000),
            requestBytes: capturedRequestBody?.count ?? request.httpBody?.count ?? 0,
            responseBytes: responseByteCount,
            errorDescription: cancelled ? nil : nsError?.localizedDescription,
            cancelled: cancelled,
            requestBody: capturedRequestBody ?? request.httpBody,
            responseBody: responseData,
            requestHeaders: request.allHTTPHeaderFields,
            responseHeaders: (capturedResponse as? HTTPURLResponse)?.allHeaderFields as? [String: String],
            timing: Self.timing(from: capturedMetrics),
            responseImageBase64: imageBase64
        )
        OlafProxySession.logQueue.async {
            Self.log(completion)
        }
    }

    // MARK: - Loglama

    /// Tamamlanan bir yakalamanın Sendable anlık görüntüsü (log kuyruğuna taşınır).
    private struct CaptureCompletion: Sendable {
        let method: String
        let url: String
        let statusCode: Int?
        let durationMs: Int
        let requestBytes: Int
        let responseBytes: Int
        let errorDescription: String?
        let cancelled: Bool
        let requestBody: Data?
        let responseBody: Data?
        let requestHeaders: [String: String]?
        let responseHeaders: [String: String]?
        let timing: NetworkTimingMetrics?
        let responseImageBase64: String?
    }

    /// Task metriklerinden zamanlama kırılımı çıkarır. Redirect'li isteklerde SON transaction
    /// (nihai kaynak) esas alınır. Yeniden kullanılan bağlantıda DNS/connect/TLS boş kalır.
    private static func timing(from metrics: URLSessionTaskMetrics?) -> NetworkTimingMetrics? {
        guard let transaction = metrics?.transactionMetrics.last else { return nil }
        func ms(_ start: Date?, _ end: Date?) -> Int? {
            guard let start, let end else { return nil }
            return Int(end.timeIntervalSince(start) * 1000)
        }
        return NetworkTimingMetrics(
            dnsMs: ms(transaction.domainLookupStartDate, transaction.domainLookupEndDate),
            connectMs: ms(transaction.connectStartDate, transaction.connectEndDate),
            tlsMs: ms(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate),
            ttfbMs: ms(transaction.requestStartDate, transaction.responseStartDate),
            protocolName: transaction.networkProtocolName,
            reusedConnection: transaction.isReusedConnection
        )
    }

    private static func log(_ completion: CaptureCompletion) {
        let config = OlafNetwork.current

        var event = NetworkLogEvent(
            method: completion.method,
            url: completion.url,
            statusCode: completion.statusCode,
            durationMs: completion.durationMs,
            requestBytes: completion.requestBytes,
            responseBytes: completion.responseBytes,
            error: completion.errorDescription,
            requestBody: nil,
            responseBody: nil,
            cancelled: completion.cancelled,
            timing: completion.timing,
            responseImageBase64: completion.responseImageBase64
        )

        if config.capturesBodies {
            event.requestBody = bodyString(from: completion.requestBody, limit: config.maxBodyLength)
            event.responseBody = bodyString(from: completion.responseBody, limit: config.maxBodyLength)
        }

        if config.capturesHeaders {
            event.requestHeaders = completion.requestHeaders
            event.responseHeaders = completion.responseHeaders
        }

        Olaf.log(
            NetworkLogComposer.level(statusCode: event.statusCode, error: event.error, cancelled: event.cancelled),
            NetworkLogComposer.message(for: event),
            category: config.category,
            metadata: NetworkLogComposer.metadata(for: event)
        )
    }

    private static func bodyString(from data: Data?, limit: Int) -> String? {
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

// MARK: - Paylaşılan proxy session

/// Tüm yakalamaların paylaştığı TEK proxy session + task → protokol yönlendiricisi.
///
/// Neden tek session? İstek başına session kurmak her yakalanan isteğe yeni TCP+TLS handshake
/// ödetir ve HTTP/2 bağlantı havuzunu kullanılamaz kılar. Tek session bağlantıları yeniden kullanır.
///
/// Config `.default` tabanlıdır → paylaşılan `HTTPCookieStorage` korunur (ephemeral'da çerezler
/// isteklere eklenmez ve `Set-Cookie` saklanmazdı → cookie tabanlı oturumlar capture altında
/// bozulurdu). Cache kapalıdır: yanıt saklama politikası istemci tarafında kalır.
final class OlafProxySession: NSObject, @unchecked Sendable {

    static let shared = OlafProxySession()

    /// Ağır log hazırlığı (JSON pretty-print) için ayrı kuyruk — delegate kuyruğunu bekletmez.
    static let logQueue = DispatchQueue(label: "com.olaf.network.log", qos: .utility)

    private let lock = NSLock()
    private var handlers: [ObjectIdentifier: OlafURLProtocol] = [:]
    private var session: URLSession?
    /// Session'ın kurulduğu andaki `chainedProtocolClasses` imzası; değişirse session yeniden kurulur.
    private var builtChainSignature: [ObjectIdentifier] = []

    private override init() { super.init() }

    // MARK: - Task yaşam döngüsü

    /// Proxy task'ı oluşturup başlatır ve handler'ı task'a bağlar. Handler, task tamamlanana
    /// (`didCompleteWithError`) dek güçlü tutulur; orada düşürülür.
    func startTask(with request: URLRequest, handler: OlafURLProtocol) -> URLSessionDataTask {
        lock.lock()
        let session = currentSessionLocked()
        lock.unlock()
        let task = session.dataTask(with: request)
        lock.lock()
        handlers[ObjectIdentifier(task)] = handler
        lock.unlock()
        task.resume()
        return task
    }

    /// Aktif session'ı döndürür; zincir değiştiyse (veya ilk kullanımsa) yeniden kurar.
    /// Eski session `finishTasksAndInvalidate` ile in-flight task'larını bitirip kapanır
    /// (callback'ler task kimliğiyle yönlendirildiğinden eski task'lar etkilenmez).
    private func currentSessionLocked() -> URLSession {
        let signature = OlafNetwork.chainedProtocolClasses.map(ObjectIdentifier.init)
        if let session, signature == builtChainSignature { return session }
        session?.finishTasksAndInvalidate()
        let fresh = URLSession(configuration: Self.makeConfiguration(), delegate: self, delegateQueue: nil)
        session = fresh
        builtChainSignature = signature
        return fresh
    }

    private static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let selfID = ObjectIdentifier(OlafURLProtocol.self)
        // Swizzle, `.default` config'e Olaf'ı enjekte etmiş olabilir → proxy'den çıkar (handledKey
        // zaten döngüyü keser ama gereksiz canInit turu da olmasın). Zincirlenen protokoller
        // (başka capture araçları) proxy trafiğini de görsün diye başa eklenir.
        let chained = OlafNetwork.chainedProtocolClasses.filter { ObjectIdentifier($0) != selfID }
        let existing = (config.protocolClasses ?? []).filter { ObjectIdentifier($0) != selfID }
        config.protocolClasses = chained + existing
        return config
    }

    private func handler(for task: URLSessionTask) -> OlafURLProtocol? {
        lock.lock(); defer { lock.unlock() }
        return handlers[ObjectIdentifier(task)]
    }

    private func removeHandler(for task: URLSessionTask) -> OlafURLProtocol? {
        lock.lock(); defer { lock.unlock() }
        return handlers.removeValue(forKey: ObjectIdentifier(task))
    }
}

// MARK: - URLSessionDataDelegate (task → handler yönlendirme)

extension OlafProxySession: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        handler(for: dataTask)?.proxyDidReceive(response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handler(for: dataTask)?.proxyDidReceive(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        handler(for: task)?.proxyWasRedirected(to: request, response: response)
        completionHandler(request)
    }

    /// Sunucu trust challenge'ı. **Varsayılan**: sistem doğrulaması (`.performDefaultHandling`) →
    /// proxy session host'un cert pinning'ini/OS trust zincirini ezmez; geçersiz/pinlenmemiş sertifika
    /// reddedilir.
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

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        handler(for: task)?.proxyDidCollect(metrics)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        removeHandler(for: task)?.proxyDidComplete(error: error)
    }
}

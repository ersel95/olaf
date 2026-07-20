import Foundation

/// `URLProtocol` that captures requests/responses and logs them to Olaf. Runs the actual request
/// through the (uncaptured) proxy session shared by all captures (`OlafProxySession`) and forwards
/// the result to the client.
final class OlafURLProtocol: URLProtocol {

    private static let handledKey = "com.olaf.network.handled"

    private var proxyTask: URLSessionDataTask?
    /// Only populated while body capture is on (`capturesBodies`); stays empty when it's off so we
    /// don't needlessly hold large downloads in RAM (the count comes from `responseByteCount` instead).
    private var responseData = Data()
    private var responseByteCount = 0
    private var capturesBodies = true
    private var capturedResponse: URLResponse?
    /// Request body: since `URLSession` converts `httpBody` to `httpBodyStream`, `request.httpBody`
    /// is usually `nil` inside the protocol; the body is captured here in `startLoading`.
    private var capturedRequestBody: Data?
    private var startDate = Date()
    /// ID of the "active requests" entry; dropped once completed (success/error/cancel).
    private var pendingID: UUID?
    /// The proxy task's timing metrics (`didFinishCollecting` — arrives before `didComplete`).
    private var capturedMetrics: URLSessionTaskMetrics?

    /// No client calls are made after `stopLoading` (the URL loading system has released the protocol).
    /// `stopLoading` comes from the client queue, proxy callbacks come from the delegate queue → lock.
    private let stateLock = NSLock()
    private var _stopped = false
    private var isStopped: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _stopped }
        set { stateLock.lock(); _stopped = newValue; stateLock.unlock() }
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        // Prevent an infinite loop: don't recapture a request we ourselves started.
        if URLProtocol.property(forKey: handledKey, in: request) != nil { return false }
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        // Mocked requests are captured even if they fall outside the capture filters (mock takes priority).
        if OlafNetwork.mock(for: request) != nil { return true }
        // baseURL allow/deny filter: requests outside the filter aren't captured (pass through as-is).
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

        // Capture the request body. `URLSession` converts `httpBody` to `httpBodyStream` before the
        // protocol sees it, so `httpBody == nil` in most POST/PUT requests. We drain the stream here,
        // both capturing it and putting it back as the proxy request's `httpBody` (the stream can only
        // be read once; if we don't put it back, the body never reaches the server). Only done while
        // body capture is on; we don't touch the stream when it's off.
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

        // If a mock matches, never hit the network: the (possibly delayed) response is produced here.
        if let mock = OlafNetwork.mock(for: request) {
            startMockDelivery(mock)
            return
        }

        proxyTask = OlafProxySession.shared.startTask(with: mutable as URLRequest, handler: self)
    }

    override func stopLoading() {
        isStopped = true
        // Cancel is a no-op on an already-completed task; a task cut short mid-flight produces
        // `didCompleteWithError(cancelled)` → logged as "cancelled" at `.info` level (the handler drops it there).
        proxyTask?.cancel()
        proxyTask = nil
        // If a mock hasn't been delivered yet, cancel it and drop the pending entry.
        if let item = mockWorkItem {
            item.cancel()
            mockWorkItem = nil
            if let pendingID {
                PendingRequestRegistry.shared.unregister(pendingID)
            }
        }
    }

    // MARK: - Mock delivery

    private var mockWorkItem: DispatchWorkItem?

    private func startMockDelivery(_ mock: OlafMockResponse) {
        let item = DispatchWorkItem { [weak self] in
            self?.deliverMock(mock)
        }
        mockWorkItem = item
        DispatchQueue.global(qos: .userInitiated)
            .asyncAfter(deadline: .now() + mock.delaySeconds, execute: item)
    }

    private func deliverMock(_ mock: OlafMockResponse) {
        mockWorkItem = nil
        if let pendingID {
            PendingRequestRegistry.shared.unregister(pendingID)
        }

        let cancelled = isStopped
        var transportErrorDescription: String?

        if let errorCode = mock.transportError {
            transportErrorDescription = URLError(errorCode).localizedDescription
            if !cancelled {
                client?.urlProtocol(self, didFailWithError: URLError(errorCode))
            }
        } else if !cancelled {
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url, statusCode: mock.statusCode,
                      httpVersion: "HTTP/1.1", headerFields: mock.headers
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !mock.body.isEmpty {
                client?.urlProtocol(self, didLoad: mock.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        let completion = CaptureCompletion(
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "-",
            statusCode: mock.transportError == nil ? mock.statusCode : nil,
            durationMs: Int(Date().timeIntervalSince(startDate) * 1000),
            requestBytes: capturedRequestBody?.count ?? request.httpBody?.count ?? 0,
            responseBytes: mock.body.count,
            errorDescription: cancelled ? nil : transportErrorDescription,
            cancelled: cancelled,
            requestBody: capturedRequestBody ?? request.httpBody,
            responseBody: mock.body,
            requestHeaders: request.allHTTPHeaderFields,
            responseHeaders: mock.headers,
            timing: nil,
            responseImageBase64: nil,
            mocked: true
        )
        OlafProxySession.logQueue.async {
            Self.log(completion)
        }
    }

    // MARK: - Proxy callbacks (forwarded from OlafProxySession's delegate queue)

    func proxyDidReceive(_ response: URLResponse) {
        capturedResponse = response
        guard !isStopped else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func proxyDidReceive(_ data: Data) {
        responseByteCount += data.count
        // If body capture is off, don't accumulate the data (only count bytes) → saves RAM on large downloads.
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

        // The heavy part (JSON pretty-print + logging) is moved to a separate queue via a Sendable
        // snapshot, so it doesn't hold up the shared delegate queue. No further callbacks arrive for
        // this task past this point → the fields are fixed, so copying them is safe.
        let nsError = error as NSError?
        let cancelled = nsError.map { $0.domain == NSURLErrorDomain && $0.code == NSURLErrorCancelled } ?? false

        // Image preview: image/* responses under the size limit are stored as base64 (shown in the detail view).
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
            responseImageBase64: imageBase64,
            mocked: false
        )
        OlafProxySession.logQueue.async {
            Self.log(completion)
        }
    }

    // MARK: - Logging

    /// Sendable snapshot of a completed capture (moved onto the log queue).
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
        let mocked: Bool
    }

    /// Derives the timing breakdown from task metrics. For redirected requests, the LAST transaction
    /// (the final source) is used. DNS/connect/TLS are empty for a reused connection.
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
            responseImageBase64: completion.responseImageBase64,
            mocked: completion.mocked
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
        // If it's JSON, pretty-print and store it at capture time → renders indented in the viewer.
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text.count > limit ? String(text.prefix(limit)) + "…" : text
        }
        guard let text = String(data: data, encoding: .utf8) else { return "<\(data.count) bytes binary>" }
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// Reads `httpBodyStream` fully and converts it to `Data`. Since the stream can only be read
    /// once, the returned data must be put back as the proxy request's `httpBody` (otherwise the
    /// body never reaches the server).
    private static func drainStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 8192
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break } // 0 = done, <0 = error
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Shared proxy session

/// The SINGLE proxy session shared by all captures, plus the task → protocol router.
///
/// Why a single session? Setting up a session per request would force a fresh TCP+TLS handshake
/// on every captured request and make the HTTP/2 connection pool unusable. A single session reuses connections.
///
/// The config is based on `.default` → the shared `HTTPCookieStorage` is preserved (with ephemeral,
/// cookies wouldn't be attached to requests and `Set-Cookie` wouldn't be stored → cookie-based
/// sessions would break under capture). Cache is disabled: the response caching policy stays on the client side.
final class OlafProxySession: NSObject, @unchecked Sendable {

    static let shared = OlafProxySession()

    /// Separate queue for heavy log prep (JSON pretty-print) — doesn't hold up the delegate queue.
    static let logQueue = DispatchQueue(label: "com.olaf.network.log", qos: .utility)

    private let lock = NSLock()
    private var handlers: [ObjectIdentifier: OlafURLProtocol] = [:]
    private var session: URLSession?
    /// The `chainedProtocolClasses` signature at the time the session was built; the session is
    /// rebuilt if it changes.
    private var builtChainSignature: [ObjectIdentifier] = []

    private override init() { super.init() }

    // MARK: - Task lifecycle

    /// Creates and starts the proxy task, binding the handler to the task. The handler is held
    /// strongly until the task completes (`didCompleteWithError`), where it is dropped.
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

    /// Returns the active session; rebuilds it if the chain changed (or this is the first use).
    /// The old session finishes its in-flight tasks and closes via `finishTasksAndInvalidate`
    /// (since callbacks are routed by task identity, old tasks are unaffected).
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
        // The swizzle may have injected Olaf into the `.default` config → strip it out of the
        // proxy (handledKey already breaks the loop, but let's avoid an unnecessary canInit pass
        // too). Chained protocols (other capture tools) are prepended so they also see proxy traffic.
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

// MARK: - URLSessionDataDelegate (task → handler routing)

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

    /// Server trust challenge. **Default**: system validation (`.performDefaultHandling`) →
    /// the proxy session doesn't override the host's cert pinning/OS trust chain; an invalid/unpinned
    /// certificate is rejected.
    ///
    /// **Opt-in (non-prod only)**: if `allowsArbitraryServerTrustForCapture == true`, the trust offered
    /// by the server is unconditionally accepted on the server-trust challenge. If the host trusts its
    /// own custom CA / internal test gateway (the capture proxy does NOT share the host's trust delegate
    /// → default validation gives TLS -9807), this flag lets capture pass that traffic through. Olaf is
    /// already compiled under `#if !PROD`.
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

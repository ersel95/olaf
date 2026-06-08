import Foundation

/// Upload sonucu.
enum OlafUploadResult: Sendable {
    /// Başarılı (2xx).
    case success
    /// Kalıcı hata (4xx — auth/şema). Tekrar denenmemeli, kuyruktan düşmeli.
    case permanentFailure(String)
    /// Geçici hata (ağ / 5xx). Kuyruğa düşüp backoff ile tekrar denenmeli.
    case transientFailure(String)
}

/// `multipart/form-data` raporu olaf-api'ye gönderen istemci.
///
/// - **Kendi `URLSession`'ı**: capture protokolü (`OlafURLProtocol`) **enjekte edilmez** →
///   upload trafiği yakalanmaz, recursion oluşmaz. (Ayrıca host, baseURL'i
///   `OlafNetwork.excludedURLs`'e ekler — çift güvence.)
final class OlafUploader: @unchecked Sendable {

    private let configuration: OlafUploadConfiguration
    private let session: URLSession

    init(configuration: OlafUploadConfiguration) {
        self.configuration = configuration
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfig.timeoutIntervalForResource = configuration.requestTimeout * 2
        sessionConfig.protocolClasses = []      // capture protokolleri YOK
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: sessionConfig)
    }

    /// Önceden serialize edilmiş bir multipart gövdeyi gönderir (kuyruk diskten okuduğunda kullanılır).
    func upload(body: Data, boundary: String) async -> OlafUploadResult {
        var request = URLRequest(url: configuration.reportsURL)
        request.httpMethod = "POST"
        request.setValue(configuration.appKey, forHTTPHeaderField: "x-olaf-app-key")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-olaf-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        do {
            let (_, response) = try await session.upload(for: request, from: body)
            guard let http = response as? HTTPURLResponse else {
                return .transientFailure("Geçersiz yanıt")
            }
            switch http.statusCode {
            case 200..<300:
                return .success
            case 400..<500:
                // 408 (timeout) ve 429 (rate limit) geçici sayılır; gerisi kalıcı.
                if http.statusCode == 408 || http.statusCode == 429 {
                    return .transientFailure("HTTP \(http.statusCode)")
                }
                return .permanentFailure("HTTP \(http.statusCode)")
            default:
                return .transientFailure("HTTP \(http.statusCode)")
            }
        } catch {
            return .transientFailure((error as NSError).localizedDescription)
        }
    }

    // MARK: - Multipart gövde üretimi

    /// `report` (JSON) + `screenshot` (JPEG binary) → multipart gövde.
    /// - Returns: (gövde verisi, boundary). Kuyruk bu ikisini birlikte saklar.
    static func makeMultipartBody(reportJSON: Data, screenshot: Data?) -> (body: Data, boundary: String) {
        let boundary = "OlafBoundary-\(UUID().uuidString)"
        var body = Data()

        func appendString(_ string: String) {
            if let data = string.data(using: .utf8) { body.append(data) }
        }

        // part: report (application/json) — sent as a named file part (with a
        // filename) so multipart parsers that don't attach text fields to the
        // request body still expose it as an uploaded part.
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"report\"; filename=\"report.json\"\r\n")
        appendString("Content-Type: application/json\r\n\r\n")
        body.append(reportJSON)
        appendString("\r\n")

        // field: screenshot (image/jpeg, binary)
        if let screenshot, !screenshot.isEmpty {
            appendString("--\(boundary)\r\n")
            appendString("Content-Disposition: form-data; name=\"screenshot\"; filename=\"screenshot.jpg\"\r\n")
            appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(screenshot)
            appendString("\r\n")
        }

        appendString("--\(boundary)--\r\n")
        return (body, boundary)
    }
}

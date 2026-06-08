import Foundation
import OlafCore

/// Diske kalıcı (offline) upload kuyruğu. Başarısız raporlar `Caches/Olaf/uploads/` altında
/// saklanır ve exponential backoff ile yeniden denenir. Süreç yeniden başlasa bile bekleyen
/// raporlar diskten okunup gönderilmeye devam eder.
///
/// Eşzamanlılık: tek bir serial `actor` üzerinde yürür → yarış yok. Disk dosyaları kendi
/// kendine yeten (multipart gövde + boundary + deneme sayısı) küçük zarflardır.
actor OlafUploadQueue {

    /// Diskte saklanan bir bekleyen upload zarfı.
    private struct Envelope: Codable {
        let id: String
        let boundary: String
        let bodyFileName: String     // ham multipart gövdesi ayrı dosyada (binary screenshot içerir)
        var attempt: Int
        let createdAt: Date
        var nextAttemptAt: Date
    }

    private let configuration: OlafUploadConfiguration
    private let uploader: OlafUploader
    private let directory: URL
    private let fileManager = FileManager.default

    /// Diske yazılan body/envelope dosyaları için koruma: cihaz kilitliyken (ve ilk açılıştan
    /// önce) içerik şifreli kalır + atomik yazım. Hassas log/screenshot içerdiğinden zorunlu.
    private static let writeOptions: Data.WritingOptions = {
        #if canImport(UIKit) || os(iOS)
        return [.atomic, .completeFileProtection]
        #else
        // macOS'ta FileProtection yok; atomik yazım korunur (testler macOS'ta da koşar).
        return [.atomic]
        #endif
    }()

    /// Kuyrukta bekleyen bir raporun maksimum yaşı. Bu süreden eski raporlar gönderilemeden
    /// silinir (bayat hassas veriyi diskte süresiz tutmamak için).
    private static let maxEnvelopeAge: TimeInterval = 48 * 60 * 60   // 48 saat

    private var isDraining = false

    init(configuration: OlafUploadConfiguration, uploader: OlafUploader) {
        self.configuration = configuration
        self.uploader = uploader
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = caches.appendingPathComponent("Olaf/uploads", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Public

    /// Bir raporu hemen göndermeyi dener. Geçici hata olursa diske kuyruklar ve `false` döner;
    /// başarıda `true`. Kalıcı hata → diske yazılmaz (anlamsız), `false`.
    @discardableResult
    func submit(reportJSON: Data, screenshot: Data?) async -> Bool {
        let (body, boundary) = OlafUploader.makeMultipartBody(reportJSON: reportJSON, screenshot: screenshot)
        let result = await uploader.upload(body: body, boundary: boundary)
        switch result {
        case .success:
            return true
        case .permanentFailure(let reason):
            Olaf.error("Bug raporu kalıcı hata ile reddedildi: \(reason)", category: .general)
            return false
        case .transientFailure(let reason):
            Olaf.warning("Bug raporu gönderilemedi, kuyruğa alındı: \(reason)", category: .general)
            persist(body: body, boundary: boundary)
            return false
        }
    }

    /// Diskteki bekleyen tüm raporları (zamanı gelenleri) sırayla göndermeyi dener.
    /// İdempotent: zaten çalışıyorsa erken döner.
    func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        let envelopes = loadEnvelopes().sorted { $0.createdAt < $1.createdAt }
        let now = Date()
        for var envelope in envelopes {
            // TTL: maksimum yaşı geçen raporlar gönderilmeden silinir (bayat hassas veri).
            if now.timeIntervalSince(envelope.createdAt) > Self.maxEnvelopeAge {
                Olaf.warning("Bug raporu süresi doldu (TTL), gönderilmeden silindi.", category: .general)
                remove(envelope)
                continue
            }
            guard envelope.nextAttemptAt <= now else { continue }
            guard let body = readBody(for: envelope) else {
                remove(envelope); continue
            }
            let result = await uploader.upload(body: body, boundary: envelope.boundary)
            switch result {
            case .success:
                remove(envelope)
            case .permanentFailure:
                remove(envelope)
            case .transientFailure:
                envelope.attempt += 1
                if envelope.attempt > configuration.maxRetryCount {
                    remove(envelope)
                } else {
                    let delay = configuration.baseRetryDelay * pow(2, Double(envelope.attempt))
                    envelope.nextAttemptAt = Date().addingTimeInterval(delay)
                    write(envelope)
                }
            }
        }
    }

    /// Kuyrukta bekleyen (süresi DOLMAMIŞ) rapor sayısı (test/diagnostik).
    /// Süresi dolmuş zarflar bu çağrıda diskten temizlenir.
    func pendingCount() -> Int {
        let now = Date()
        var live = 0
        for envelope in loadEnvelopes() {
            if now.timeIntervalSince(envelope.createdAt) > Self.maxEnvelopeAge {
                remove(envelope)
            } else {
                live += 1
            }
        }
        return live
    }

    // MARK: - Disk

    private func persist(body: Data, boundary: String) {
        let id = UUID().uuidString
        let bodyFileName = "\(id).body"
        do {
            try body.write(to: directory.appendingPathComponent(bodyFileName), options: Self.writeOptions)
        } catch {
            return
        }
        let envelope = Envelope(
            id: id,
            boundary: boundary,
            bodyFileName: bodyFileName,
            attempt: 0,
            createdAt: Date(),
            nextAttemptAt: Date().addingTimeInterval(configuration.baseRetryDelay)
        )
        write(envelope)
    }

    private func envelopeURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    private func write(_ envelope: Envelope) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: envelopeURL(envelope.id), options: Self.writeOptions)
    }

    private func readBody(for envelope: Envelope) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(envelope.bodyFileName))
    }

    private func remove(_ envelope: Envelope) {
        try? fileManager.removeItem(at: envelopeURL(envelope.id))
        try? fileManager.removeItem(at: directory.appendingPathComponent(envelope.bodyFileName))
    }

    private func loadEnvelopes() -> [Envelope] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Envelope? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Envelope.self, from: data)
            }
    }
}

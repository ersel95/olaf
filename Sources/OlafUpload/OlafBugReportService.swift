import Foundation
import OlafCore

/// Bug-reporter çalışma motoru: payload toplama + kuyruğa gönderme + remote config gate.
///
/// OlafUI (screenshot detector / banner / sheet) bu servisi `OlafUpload.bugReportService`
/// üzerinden kullanır. Servis yalnız `OlafUpload.configure(enabled: true, ...)` çağrıldığında
/// ve `appKey` geçerliyse var olur; aksi halde `nil` → UI hiçbir şey kurmaz/göstermez.
public final class OlafBugReportService: @unchecked Sendable {

    private let configuration: OlafUploadConfiguration
    private let queue: OlafUploadQueue
    private let remoteConfigClient: OlafRemoteConfigClient

    /// Bug-reporter, **build redaksiyon ayarından bağımsız olarak** upload edilecek log'ları
    /// zorla redakte eder (banking-grade). Server yalnız DAHA kısıtlayıcı olabilir
    /// (redaksiyonu zorlayabilir), gevşetemez. Bu yüzden bu redaktör sabittir.
    private let redactor: any Redactor

    private let lock = NSLock()
    private var _remoteConfig: OlafRemoteConfig = .disabled

    init(configuration: OlafUploadConfiguration) {
        self.configuration = configuration
        let uploader = OlafUploader(configuration: configuration)
        self.queue = OlafUploadQueue(configuration: configuration, uploader: uploader)
        self.remoteConfigClient = OlafRemoteConfigClient(configuration: configuration)
        self.redactor = BankingRedactor()
    }

    // MARK: - Lifecycle (configure'dan çağrılır)

    /// Remote config'i çeker (server-side kill-switch) ve bekleyen kuyruğu boşaltmayı dener.
    func bootstrap() {
        Task {
            let config = await remoteConfigClient.fetch()
            self.setRemoteConfig(config)
            await self.queue.drain()
        }
    }

    /// Bekleyen offline raporları göndermeyi dener (örn. uygulama foreground'a dönünce).
    public func flushPendingUploads() {
        Task { await queue.drain() }
    }

    // MARK: - Capture gate

    /// Yakalama şu an aktif mi? İki gate: (1) local `enabled` (zaten servis varsa true) →
    /// (2) server-side `captureEnabled`. Banner yalnız bu `true` iken gösterilir.
    public var isCaptureEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _remoteConfig.captureEnabled
    }

    /// Remote config'ten gelen screenshot byte sınırı (config default'unu ezebilir).
    public var maxScreenshotBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return min(configuration.maxScreenshotBytes, _remoteConfig.maxScreenshotBytes)
    }

    /// JPEG sıkıştırma kalitesi.
    public var screenshotJPEGQuality: Double { configuration.screenshotJPEGQuality }

    /// Server'ın istediği redaksiyon durumu. Bug-reporter zaten her zaman redakte ettiğinden
    /// bu yalnız **daha kısıtlayıcı** yönde anlamlıdır (server redaksiyonu zorlayabilir, kapatamaz).
    /// Diagnostik/şeffaflık için açığa çıkarılır.
    public var remoteRedactionEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _remoteConfig.redactionEnabled
    }

    private func setRemoteConfig(_ config: OlafRemoteConfig) {
        lock.lock(); _remoteConfig = config; lock.unlock()
    }

    // MARK: - Identity (sheet ilk açılışta isim sorar mı?)

    /// Daha önce tester ismi girilmiş mi?
    public var hasStoredTesterName: Bool { OlafDeviceIdentity.hasStoredName }

    /// Bir kerelik tester ismini saklar.
    public func storeTesterName(_ name: String) { OlafDeviceIdentity.storeName(name) }

    // MARK: - Gönderim

    /// Rapor gönderir. Snapshot + screenshot + meta + kimlik + iki alan toplanır, multipart
    /// olarak yüklenir. Başarıda `true`; geçici hatada kuyruğa düşer ve `false` döner.
    ///
    /// - Parameters:
    ///   - whatHappened: "Ne yaşadın?" alanı.
    ///   - whatExpected: "Ne olmalıydı?" alanı.
    ///   - testerName: İlk gönderimde girilen isim (sonra saklanır); nil ise saklı isim kullanılır.
    ///   - screenshotJPEG: Önceden JPEG'e sıkıştırılmış ekran görüntüsü (binary).
    ///   - identity: Cihaz kimliği (UI MainActor'da toplar).
    @discardableResult
    public func sendReport(
        whatHappened: String,
        whatExpected: String,
        testerName: String?,
        screenshotJPEG: Data?,
        identity: OlafDeviceIdentity
    ) async -> Bool {
        if let testerName, !testerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            OlafDeviceIdentity.storeName(testerName)
        }
        let effectiveName = testerName ?? identity.name ?? OlafDeviceIdentity.storedName()

        // FAIL-CLOSED REDAKSİYON: upload edilecek log'lar build redaksiyon ayarından bağımsız
        // olarak BankingRedactor'dan ZORLA geçirilir (server yalnız daha kısıtlayıcı olabilir).
        // Redaksiyon hiçbir şekilde uygulanamıyorsa (redaktör NoopRedactor'a düşmüşse) upload iptal.
        guard !(redactor is NoopRedactor) else {
            Olaf.error(
                "Bug raporu iptal edildi: redaksiyon uygulanamıyor (fail-closed).",
                category: .general
            )
            return false
        }
        let redactedEntries = redactor.redact(entries: Olaf.snapshot())

        let payload = OlafReportPayload(
            app: .init(
                key: configuration.appKey,
                bundleId: OlafDeviceIdentity.bundleIdentifier,
                version: OlafDeviceIdentity.appVersion,
                build: OlafDeviceIdentity.appBuild,
                environment: configuration.environment
            ),
            device: .init(
                id: identity.id,
                name: effectiveName,
                model: identity.model,
                osVersion: identity.osVersion,
                locale: identity.locale,
                screen: identity.screen
            ),
            report: .init(
                whatHappened: whatHappened,
                whatExpected: whatExpected,
                capturedAt: Self.iso8601String(from: Date()),
                sessionId: Olaf.currentSessionID
            ),
            entries: redactedEntries   // TÜM kategoriler, ZORLA redakte edilmiş LogEntry[]
        )

        guard let reportJSON = try? payload.encodedJSON() else { return false }
        return await queue.submit(reportJSON: reportJSON, screenshot: screenshotJPEG)
    }

    /// ISO-8601 zaman damgası. Her çağrıda yerel formatter kullanır (paylaşılan mutable state yok →
    /// Sendable-safe). Gönderim sıklığı düşük olduğundan maliyet ihmal edilebilir.
    private static func iso8601String(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

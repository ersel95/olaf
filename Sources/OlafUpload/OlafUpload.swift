import Foundation
import OlafCore
#if canImport(OlafNetwork)
import OlafNetwork
#endif

/// Bug-reporter (screenshot → banner → upload) cephesi. **OPT-IN, varsayılan KAPALI.**
///
/// `configure(...)` çağrılmadıkça veya `enabled: false` (varsayılan) ile çağrıldıkça **hiçbir**
/// remote config / screenshot detector / navigation tracker / upload kodu çalışmaz. Shake → log
/// görüntüleme (OlafUI viewer) bundan tamamen bağımsızdır, etkilenmez.
///
/// ```swift
/// // Default: kapalı. Açmak için (host xcconfig'ten değerleri sağlar):
/// OlafUpload.configure(
///     enabled: true,
///     appKey: "<APP_KEY>",
///     apiKey: "<API_KEY>",
///     baseURL: URL(string: "<BASE_URL>")!,
///     environment: "staging"
/// )
/// ```
///
/// İki gate: (1) local `enabled` (build-time) → (2) server-side `captureEnabled` (`GET /config`).
public enum OlafUpload {

    private static let box = StateBox()

    // MARK: - Configure (tek giriş noktası)

    /// Bug-reporter'ı yapılandırır. **Varsayılan `enabled: false`** → opt-in.
    ///
    /// - `enabled == false` → **erken return**: remote config YOK, detector YOK, tracker YOK,
    ///   upload YOK. Sıfır ağ aktivitesi.
    /// - `enabled == true` ama `appKey` boş → no-op + dev uyarısı (hangi projeden config
    ///   çekileceği bilinemez).
    ///
    /// İdempotenttir; tekrar çağrılırsa ilki korunur.
    public static func configure(
        enabled: Bool = false,
        appKey: String = "",
        apiKey: String = "",
        baseURL: URL,
        environment: String = "staging"
    ) {
        let config = OlafUploadConfiguration(
            enabled: enabled,
            appKey: appKey,
            apiKey: apiKey,
            baseURL: baseURL,
            environment: environment
        )
        configure(with: config)
    }

    /// Tam yapılandırma nesnesiyle kurar (gelişmiş kullanım / test).
    ///
    /// SAVUNMA KATMANLARI (release'de yanlışlıkla aktivasyona karşı):
    ///  1. Build-time opt-in (`enabled`): varsayılan `false`. Bu gate geçilmeden hiçbir ağ/
    ///     detector/tracker/upload kodu çalışmaz (aşağıdaki erken return).
    ///  2. Runtime kill-switch (server `captureEnabled`, `GET /config`): TEK runtime anahtarı —
    ///     `enabled: true` olsa bile server kapalıysa banner gösterilmez/yakalama yapılmaz.
    ///     Bu davranış `OlafBugReportService.isCaptureEnabled` üzerinden korunur; bozulmamalıdır.
    ///  3. Fail-closed: remote config çekilemezse `.disabled` (kapalı) varsayılır.
    /// Host, release build'lerde `enabled`'ı asla sabit `true` ile geçmemelidir; değer
    /// xcconfig/secrets üzerinden (yalnız non-prod) sağlanmalıdır.
    public static func configure(with configuration: OlafUploadConfiguration) {
        // Gate 1: local opt-in (build-time savunma). Kapalıysa hiçbir şey yapma — erken return.
        guard configuration.enabled else { return }

        // appKey zorunlu.
        guard !configuration.appKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            Olaf.warning(
                "OlafUpload.configure: appKey boş — bug-reporter başlatılmadı (remote config çekilemez).",
                category: .general
            )
            return
        }

        // İdempotent: zaten kurulduysa ilkini koru.
        guard box.service == nil else { return }

        let service = OlafBugReportService(configuration: configuration)
        box.service = service

        // Recursion önleme: upload + config endpoint'lerini capture'dan hariç tut.
        excludeUploadURLsFromCapture(configuration)

        // Remote config çek (server-side kill-switch) + bekleyen kuyruğu boşalt.
        service.bootstrap()

        // UI tarafı (screenshot detector + banner). OlafUI önceden bir installer kaydetmişse
        // burada tetiklenir; OlafUpload doğrudan UIKit/OlafUI'a bağımlı değildir.
        box.detectorInstaller?()
    }

    // MARK: - Erişim

    /// Aktif bug-reporter servisi. `configure(enabled: true, appKey:...)` çağrılmadıysa `nil`.
    /// OlafUI bunu kullanarak rapor besler; `nil` ise hiçbir UI kurmaz.
    public static var bugReportService: OlafBugReportService? {
        box.service
    }

    /// Bug-reporter şu an etkin mi? (configure edilmiş + servis var)
    public static var isConfigured: Bool { box.service != nil }

    /// OlafUI bu hook ile screenshot detector/banner kurulum closure'ını kaydeder.
    /// `configure(enabled: true)` başarılı olursa Olaf tarafından çağrılır. Eğer configure
    /// zaten yapılmışsa, hook kaydı anında tetiklenir (sıra bağımsızlığı).
    public static func setDetectorInstaller(_ installer: @escaping @Sendable () -> Void) {
        box.detectorInstaller = installer
        if box.service != nil {
            installer()
        }
    }

    /// Bekleyen offline raporları göndermeyi dener (örn. foreground'a dönüşte).
    public static func flushPendingUploads() {
        box.service?.flushPendingUploads()
    }

    // MARK: - Recursion önleme

    private static func excludeUploadURLsFromCapture(_ configuration: OlafUploadConfiguration) {
        #if canImport(OlafNetwork)
        var networkConfig = OlafNetwork.configuration
        for fragment in configuration.captureExclusionFragments
        where !networkConfig.excludedURLs.contains(fragment) {
            networkConfig.excludedURLs.append(fragment)
        }
        OlafNetwork.configuration = networkConfig
        #endif
    }

    // MARK: - State

    private final class StateBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _service: OlafBugReportService?
        private var _installer: (@Sendable () -> Void)?

        var service: OlafBugReportService? {
            get { lock.lock(); defer { lock.unlock() }; return _service }
            set { lock.lock(); _service = newValue; lock.unlock() }
        }
        var detectorInstaller: (@Sendable () -> Void)? {
            get { lock.lock(); defer { lock.unlock() }; return _installer }
            set { lock.lock(); _installer = newValue; lock.unlock() }
        }
    }
}

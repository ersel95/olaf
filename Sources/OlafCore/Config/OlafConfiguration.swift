import Foundation

/// Olaf çekirdeğinin yapılandırması. `Olaf.start(_:)` ile bir kez verilir.
public struct OlafConfiguration: Sendable {

    /// Bu seviyenin altındaki loglar tamamen göz ardı edilir (mesaj bile compute edilmez).
    public var minimumLevel: LogLevel

    /// In-memory ring buffer kapasitesi (en yeni N kayıt RAM'de tutulur).
    public var inMemoryCapacity: Int

    /// Logları diske de yazsın mı? (uygulama yeniden başladıktan sonra erişim için)
    public var persistsToDisk: Bool

    /// Aktif log dosyası bu boyutu (byte) aşınca rotate edilir.
    public var maxFileSize: Int

    /// Diskte tutulacak en fazla dosya sayısı (eskiler silinir).
    public var maxFileCount: Int

    /// Redaksiyon kuralları çalışsın mı? `true` → `redactor` uygulanır (her şey maskelenir);
    /// `false` → hiçbir şey gizlenmez (ham veri saklanır). **Varsayılan `false`**.
    public var redactionEnabled: Bool

    /// `redactionEnabled == true` iken yazma anında uygulanan redaksiyon (banking-grade).
    /// Kapalıyken yok sayılır.
    public var redactor: any Redactor

    /// Yazma anında gerçekten uygulanacak redaktör: redaksiyon kapalıysa hiçbir şey yapmayan
    /// `NoopRedactor`, açıksa yapılandırılmış `redactor`.
    public var effectiveRedactor: any Redactor {
        redactionEnabled ? redactor : NoopRedactor()
    }

    /// Export (.log paylaşımı) sırasında kullanılan **insan-okur** biçim. Disk depolaması
    /// her zaman NDJSON'dur (geri okunabilirlik için); bu formatter yalnız paylaşım metnini üretir.
    public var exportFormatter: any LogFormatter

    /// OSLog (`os.Logger`) köprüsü — loglar Console.app'te de görünsün mü?
    public var mirrorsToOSLog: Bool

    /// OSLog köprüsü için subsystem (genelde bundle id).
    public var subsystem: String

    public init(
        minimumLevel: LogLevel = .trace,   // default açık: tüm seviyeler yakalanır
        inMemoryCapacity: Int = 2000,
        persistsToDisk: Bool = true,
        maxFileSize: Int = 1_048_576,        // 1 MB
        maxFileCount: Int = 5,
        redactionEnabled: Bool = false,
        redactor: any Redactor = BankingRedactor(),
        exportFormatter: any LogFormatter = PlainTextFormatter(),
        mirrorsToOSLog: Bool = true,
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.olaf"
    ) {
        self.minimumLevel = minimumLevel
        self.inMemoryCapacity = max(1, inMemoryCapacity)
        self.persistsToDisk = persistsToDisk
        self.maxFileSize = max(4096, maxFileSize)
        self.maxFileCount = max(1, maxFileCount)
        self.redactionEnabled = redactionEnabled
        self.redactor = redactor
        self.exportFormatter = exportFormatter
        self.mirrorsToOSLog = mirrorsToOSLog
        self.subsystem = subsystem
    }

    /// Genel amaçlı varsayılan.
    public static let `default` = OlafConfiguration()

    /// Bankacılık uygulamaları için önerilen profil (redaksiyon **açık**, diske yazar).
    /// `BankingRedactor` ile network gövdeleri (`requestBody`/`responseBody`) JSON ise
    /// derin key-bazlı (token/balance/iban/pan/cvv…) recursive maskelemeden geçer; gövde
    /// redaksiyonu bu profilde her zaman uygulanır.
    public static let bankingDefault = OlafConfiguration(
        minimumLevel: .trace,   // default açık: tüm seviyeler
        inMemoryCapacity: 3000,
        persistsToDisk: true,
        redactionEnabled: true,
        redactor: BankingRedactor()
    )
}

import Foundation

/// LogFox çekirdeğinin yapılandırması. `LogFox.start(_:)` ile bir kez verilir.
public struct LogFoxConfiguration: Sendable {

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

    /// Yazma anında uygulanan redaksiyon. Varsayılan banking-grade ve **açık**.
    public var redactor: any Redactor

    /// Export (.log paylaşımı) sırasında kullanılan **insan-okur** biçim. Disk depolaması
    /// her zaman NDJSON'dur (geri okunabilirlik için); bu formatter yalnız paylaşım metnini üretir.
    public var exportFormatter: any LogFormatter

    /// OSLog (`os.Logger`) köprüsü — loglar Console.app'te de görünsün mü?
    public var mirrorsToOSLog: Bool

    /// OSLog köprüsü için subsystem (genelde bundle id).
    public var subsystem: String

    public init(
        minimumLevel: LogLevel = .debug,
        inMemoryCapacity: Int = 2000,
        persistsToDisk: Bool = true,
        maxFileSize: Int = 1_048_576,        // 1 MB
        maxFileCount: Int = 5,
        redactor: any Redactor = BankingRedactor(),
        exportFormatter: any LogFormatter = PlainTextFormatter(),
        mirrorsToOSLog: Bool = true,
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.logfox"
    ) {
        self.minimumLevel = minimumLevel
        self.inMemoryCapacity = max(1, inMemoryCapacity)
        self.persistsToDisk = persistsToDisk
        self.maxFileSize = max(4096, maxFileSize)
        self.maxFileCount = max(1, maxFileCount)
        self.redactor = redactor
        self.exportFormatter = exportFormatter
        self.mirrorsToOSLog = mirrorsToOSLog
        self.subsystem = subsystem
    }

    /// Genel amaçlı varsayılan.
    public static let `default` = LogFoxConfiguration()

    /// Bankacılık uygulamaları için önerilen profil (redaksiyon açık, diske yazar).
    public static let bankingDefault = LogFoxConfiguration(
        minimumLevel: .debug,
        inMemoryCapacity: 3000,
        persistsToDisk: true,
        redactor: BankingRedactor()
    )
}

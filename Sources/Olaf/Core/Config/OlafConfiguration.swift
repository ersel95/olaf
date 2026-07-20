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
        exportFormatter: any LogFormatter = PlainTextFormatter(),
        mirrorsToOSLog: Bool = true,
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.olaf"
    ) {
        self.minimumLevel = minimumLevel
        self.inMemoryCapacity = max(1, inMemoryCapacity)
        self.persistsToDisk = persistsToDisk
        self.maxFileSize = max(4096, maxFileSize)
        self.maxFileCount = max(1, maxFileCount)
        self.exportFormatter = exportFormatter
        self.mirrorsToOSLog = mirrorsToOSLog
        self.subsystem = subsystem
    }

    /// Genel amaçlı varsayılan.
    public static let `default` = OlafConfiguration()
}

import Foundation
import OSLog

extension Olaf {

    /// Sistemin OSLog deposundan **bu sürecin** kayıtlarını Olaf'a aktarır — diğer SDK'ların
    /// `os_log`/`Logger` çıktıları dahil. Böylece Olaf'ı bilmeyen kütüphanelerin logları da
    /// viewer'daki tek listede görünür/paylaşılır.
    ///
    /// - Kayıtlar **özgün zaman damgasıyla** eklenir ama liste ekleme sırasına göre gösterilir:
    ///   içe aktarılan blok, listede çağrı anının üstünde grup hâlinde görünür.
    /// - Olaf'ın kendi OSLog aynası (`mirrorsToOSLog`) çift kayıt üretmesin diye, `excludingSubsystems`
    ///   verilmezse **ana bundle identifier'ı** (default ayna subsystem'i) hariç tutulur; ayna için
    ///   özel `subsystem` verdiyseniz onu geçirin.
    /// - Ağır okuma `.utility` önceliğinde arka planda yapılır; çağıran bloke olmaz.
    ///
    /// - Parameters:
    ///   - since: Bu tarihten itibaren kayıtlar okunur (örn. `Date().addingTimeInterval(-3600)`).
    ///   - category: Kayıtların düşeceği Olaf kategorisi (varsayılan `.oslog`).
    ///   - excludingSubsystems: Atlanacak subsystem'ler. `nil` → ana bundle id hariç tutulur.
    /// - Returns: İçe aktarılan kayıt sayısı. Olaf başlatılmadıysa `0`.
    @discardableResult
    public static func importOSLogEntries(
        since: Date,
        category: LogCategory = .oslog,
        excludingSubsystems: [String]? = nil
    ) async throws -> Int {
        guard let store = runtime.store else { return 0 }
        let excluded = Set(excludingSubsystems ?? [Bundle.main.bundleIdentifier ?? "com.olaf"])

        return try await Task.detached(priority: .utility) {
            let osStore = try OSLogStore(scope: .currentProcessIdentifier)
            let position = osStore.position(date: since)
            var imported = 0
            for case let log as OSLogEntryLog in try osStore.getEntries(at: position) {
                guard !excluded.contains(log.subsystem) else { continue }
                store.ingest(
                    date: log.date,
                    level: mapOSLogLevel(log.level),
                    category: category,
                    rawMessage: log.composedMessage,
                    rawMetadata: [
                        "source": "oslog",
                        "subsystem": log.subsystem,
                        "osCategory": log.category
                    ],
                    file: "OSLog",
                    line: 0,
                    function: "-",
                    thread: "-"
                )
                imported += 1
            }
            return imported
        }.value
    }

    /// OSLog → Olaf seviye eşlemesi. (internal: test edilir.)
    static func mapOSLogLevel(_ level: OSLogEntryLog.Level) -> LogLevel {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .error: return .error
        case .fault: return .critical
        case .undefined: return .info
        @unknown default: return .info
        }
    }
}

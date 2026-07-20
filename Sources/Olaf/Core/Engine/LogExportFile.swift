import Foundation

/// Logları paylaşılabilir geçici `.log` dosyasına yazan ortak yardımcı.
///
/// Hem tam geçmiş export'u (`FilePersistence.consolidatedTextURL`) hem de viewer'daki
/// **filtreli** export (`LogStore.exportFileURL(entries:)`) buradan geçer; böylece tmp temizleme
/// ve dosya adlandırma tek yerde kalır.
enum LogExportFile {

    static let prefix = "olaf-export-"

    /// Verilen metni tmp'de paylaşılabilir bir dosyaya yazar (`.log` veya `.ndjson`); önce eski
    /// export'ları temizler (hassas log tmp'de süresiz birikmesin). Başarısızlıkta `nil`.
    static func write(_ text: String, fileExtension: String = "log", fileManager: FileManager = .default) -> URL? {
        purgeOld(fileManager: fileManager)
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("\(prefix)\(Int(Date().timeIntervalSince1970)).\(fileExtension)")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// tmp'deki eski `olaf-export-*` dosyalarını (.log/.ndjson) siler (yeni export'tan önce çağrılır).
    static func purgeOld(fileManager: FileManager = .default) {
        let tmp = fileManager.temporaryDirectory
        let contents = (try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: url)
        }
    }
}

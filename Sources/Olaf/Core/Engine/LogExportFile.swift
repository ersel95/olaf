import Foundation

/// Shared helper that writes logs to a shareable temporary `.log` file.
///
/// Both the full-history export (`FilePersistence.consolidatedTextURL`) and the viewer's
/// **filtered** export (`LogStore.exportFileURL(entries:)`) go through here; this keeps tmp
/// cleanup and file naming in one place.
enum LogExportFile {

    static let prefix = "olaf-export-"

    /// Writes the given text to a shareable file in tmp (`.log` or `.ndjson`); first purges old
    /// exports (so sensitive logs don't accumulate indefinitely in tmp). Returns `nil` on failure.
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

    /// Deletes old `olaf-export-*` files (.log/.ndjson) from tmp (called before a new export).
    static func purgeOld(fileManager: FileManager = .default) {
        let tmp = fileManager.temporaryDirectory
        let contents = (try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: url)
        }
    }
}

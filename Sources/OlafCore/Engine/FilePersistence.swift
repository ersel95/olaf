import Foundation

/// Logları diske **NDJSON** (satır başına bir JSON `LogEntry`) olarak yazar; boyut bazlı
/// rotation ve dosya-sayısı retention uygular. NDJSON sayesinde kayıtlar tam doğrulukla
/// geri okunabilir (oturumlar arası geçmiş). Export ise insan-okur düz metne dönüştürülür.
///
/// Bu tip **kendi başına thread-safe değildir**; yalnızca `LogStore`'un serial
/// kuyruğundan çağrılır. `@unchecked Sendable` bu sözleşmeye dayanır.
final class FilePersistence: @unchecked Sendable {

    private let directory: URL
    private let maxFileSize: Int
    private let maxFileCount: Int
    private let fileManager = FileManager.default

    private let activeFileName = "olaf-current.ndjson"
    private let rotatedPrefix = "olaf-"
    private let fileExtension = "ndjson"

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var handle: FileHandle?
    private var currentSize: Int = 0
    /// Aynı saniye içinde birden çok rotation olduğunda dosya adı çakışmasını (→ log kaybı)
    /// önlemek için monotonik sayaç. Serial kuyrukta arttığından yarış yoktur.
    private var rotationCounter = 0

    init?(directory: URL, maxFileSize: Int, maxFileCount: Int) {
        self.directory = directory
        self.maxFileSize = maxFileSize
        self.maxFileCount = maxFileCount

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try openActiveFile()
            pruneOldFiles()
        } catch {
            return nil
        }
    }

    deinit {
        try? handle?.close()
    }

    // MARK: - Yazma

    func write(_ entry: LogEntry) {
        guard let handle, let json = try? encoder.encode(entry) else { return }
        var data = json
        data.append(0x0A) // '\n'
        do {
            // Handle açılışta (ve rotate'te) sona konumlandırılır; tek yazıcı olduğundan pointer
            // sonda kalır → her yazımda `seekToEnd()` syscall'ı gereksiz, kaldırıldı.
            try handle.write(contentsOf: data)
            currentSize += data.count
            if currentSize >= maxFileSize {
                rotate()
            }
        } catch {
            // Disk hatası logging'i çökertmemeli; sessizce geç.
        }
    }

    // MARK: - Okuma (oturumlar arası geçmiş)

    /// Diskteki tüm kayıtları (eskiden yeniye) ayrıştırıp döndürür. Bozuk satırlar atlanır.
    func loadEntries() -> [LogEntry] {
        try? handle?.synchronize()
        var result: [LogEntry] = []
        for file in rotatedFilesSortedAscending() + [activeFileURL] {
            // NDJSON'u Data olarak okuyup `\n` (0x0A) üzerinden böl → her satırı String'e çevirip
            // tekrar UTF-8'e encode etme (çift dönüşüm) maliyetinden kaçınılır.
            guard let data = try? Data(contentsOf: file) else { continue }
            for lineData in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                guard let entry = try? decoder.decode(LogEntry.self, from: lineData) else { continue }
                result.append(entry)
            }
        }
        return result
    }

    // MARK: - Temizleme & export

    func clear() {
        try? handle?.close()
        handle = nil
        for url in allLogFiles() {
            try? fileManager.removeItem(at: url)
        }
        try? openActiveFile()
    }

    /// Diskteki tüm kayıtları, verilen formatter ile **insan-okur düz metin** bir dosyaya
    /// dönüştürür ve paylaşılabilir URL döndürür.
    func consolidatedTextURL(using formatter: any LogFormatter) -> URL? {
        let text = loadEntries().map { formatter.string(from: $0) }.joined(separator: "\n")
        return LogExportFile.write(text, fileManager: fileManager)
    }

    // MARK: - Dahili

    private var activeFileURL: URL {
        directory.appendingPathComponent(activeFileName)
    }

    private func openActiveFile() throws {
        if !fileManager.fileExists(atPath: activeFileURL.path) {
            fileManager.createFile(atPath: activeFileURL.path, contents: nil)
        }
        applyProtection(to: activeFileURL)
        let handle = try FileHandle(forWritingTo: activeFileURL)
        self.handle = handle
        self.currentSize = (try? handle.seekToEnd()).map(Int.init) ?? 0
    }

    private func rotate() {
        try? handle?.close()
        handle = nil

        rotationCounter += 1
        let stamp = Int(Date().timeIntervalSince1970)
        // Saniye (sabit genişlik) + monotonik sayaç → aynı saniyedeki çok sayıda rotation çakışmaz.
        var rotatedURL = directory.appendingPathComponent(
            String(format: "\(rotatedPrefix)%010d-%06d.\(fileExtension)", stamp, rotationCounter)
        )
        // Süreç yeniden başlayıp aynı saniyede rotate ederse (sayaç sıfırlanır) yine de benzersizleştir.
        if fileManager.fileExists(atPath: rotatedURL.path) {
            rotatedURL = directory.appendingPathComponent(
                "\(rotatedPrefix)\(stamp)-\(UUID().uuidString.prefix(8)).\(fileExtension)"
            )
        }
        try? fileManager.moveItem(at: activeFileURL, to: rotatedURL)

        currentSize = 0
        try? openActiveFile()
        pruneOldFiles()
    }

    /// `maxFileCount`'u aşan en eski rotated dosyaları siler (aktif dosya hariç).
    private func pruneOldFiles() {
        let rotated = rotatedFilesSortedAscending()
        // Aktif dosya da sayıma dahil → en fazla (maxFileCount - 1) rotated tutulur.
        let allowedRotated = max(0, maxFileCount - 1)
        guard rotated.count > allowedRotated else { return }
        for url in rotated.prefix(rotated.count - allowedRotated) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func allLogFiles() -> [URL] {
        rotatedFilesSortedAscending() + [activeFileURL]
    }

    private func rotatedFilesSortedAscending() -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []

        return contents
            .filter {
                $0.lastPathComponent.hasPrefix(rotatedPrefix)
                    && $0.lastPathComponent != activeFileName
                    && $0.pathExtension == fileExtension
            }
            // Önce oluşturma tarihi (isim şemasından bağımsız doğru kronolojik sıra), eşitlikte isim.
            .sorted { lhs, rhs in
                let lDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                let rDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                if let lDate, let rDate, lDate != rDate { return lDate < rDate }
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
    }

    private func applyProtection(to url: URL) {
        // İlk kilit açılışına kadar şifreli; banking-grade taban koruma.
        // `FileProtectionType` yalnız iOS/iPadOS'ta mevcut (macOS test build'inde no-op).
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}

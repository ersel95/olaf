import Foundation

/// Olaf'un çekirdek deposu: in-memory ring buffer → (ops.) disk → canlı yayın.
///
/// Tüm mutasyon tek bir serial kuyrukta yapılır → kayıt sırası deterministiktir ve
/// veri yarışı yoktur. `@unchecked Sendable` bu serial-kuyruk sözleşmesine dayanır.
final class LogStore: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.olaf.store", qos: .utility)
    private let capacity: Int
    private let persistence: FilePersistence?
    private let exportFormatter: any LogFormatter
    private let osLogMirror: OSLogMirror?
    private let sessionID: String

    /// Sabit kapasiteli halka tampon (en yeni `capacity` kayıt).
    /// `ring` kapasiteye ulaşana dek büyür; dolunca `head`'deki (en eski) kayıt üzerine yazılır.
    /// Append + evict **O(1)** (eski `Array.removeFirst` O(n) kaydırması yerine).
    private var ring: [LogEntry] = []
    /// Tampon doluyken en eski kaydın `ring` içindeki indeksi.
    private var head = 0
    /// Canlı dinleyiciler (viewer). Kuyrukta erişilir.
    private var continuations: [UUID: AsyncStream<LogEntry>.Continuation] = [:]

    /// Tampondaki kayıtlar (eskiden yeniye), kuyruk içinde çağrılır.
    private var orderedBuffer: [LogEntry] {
        if ring.count < capacity { return ring }   // dolmadıysa head == 0, ekleme sırası korunur
        return Array(ring[head...] + ring[..<head])
    }

    init(
        capacity: Int,
        persistence: FilePersistence?,
        exportFormatter: any LogFormatter,
        osLogMirror: OSLogMirror?,
        sessionID: String
    ) {
        self.capacity = capacity
        self.persistence = persistence
        self.exportFormatter = exportFormatter
        self.osLogMirror = osLogMirror
        self.sessionID = sessionID
        self.ring.reserveCapacity(capacity)
    }

    // MARK: - Yazma

    /// Çağrı yerinden gelen veriyi alıp serial kuyrukta tampona/diske yazar.
    func ingest(
        date: Date,
        level: LogLevel,
        category: LogCategory,
        rawMessage: String,
        rawMetadata: [String: String],
        file: String,
        line: Int,
        function: String,
        thread: String
    ) {
        queue.async { [self] in
            let entry = LogEntry(
                date: date,
                level: level,
                category: category,
                message: rawMessage,
                metadata: rawMetadata,
                file: file,
                line: line,
                function: function,
                thread: thread,
                sessionID: sessionID
            )

            if ring.count < capacity {
                ring.append(entry)
            } else {
                ring[head] = entry            // en eski kaydın üzerine yaz
                head = (head + 1) % capacity  // O(1) evict
            }

            persistence?.write(entry)
            osLogMirror?.log(entry)

            for continuation in continuations.values {
                continuation.yield(entry)
            }
        }
    }

    // MARK: - Okuma

    /// Mevcut tampondaki tüm kayıtların anlık kopyası (eskiden yeniye).
    func snapshot() -> [LogEntry] {
        queue.sync { orderedBuffer }
    }

    /// `snapshot()`'ın bloke etmeyen sürümü: çağıran (ör. ana thread) `.utility` kuyruğu yoğun
    /// yazma burst'ü işlerken `queue.sync` ile beklemesin diye.
    func snapshotAsync() async -> [LogEntry] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: orderedBuffer)
            }
        }
    }

    /// Yeni kayıtları canlı yayınlayan akış. Viewer abone olur.
    func makeStream() -> AsyncStream<LogEntry> {
        // Sınırlı tampon: viewer yavaşsa (veya duraklatılmışsa) bellek sınırsız büyümesin —
        // en yeni `capacity` kayıt tutulur, eskiler düşer (tampon zaten en yeniyi gösterir).
        AsyncStream(bufferingPolicy: .bufferingNewest(capacity)) { continuation in
            let id = UUID()
            queue.async { [self] in
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    // MARK: - Yönetim

    func clear() {
        queue.async { [self] in
            ring.removeAll(keepingCapacity: true)
            head = 0
            persistence?.clear()
        }
    }

    /// Diskteki tüm kayıtları (oturumlar arası geçmiş dahil) ASENKRON ayrıştırır.
    /// Ağır dosya I/O serial kuyrukta yapılır → çağıran (ör. ana thread) bloke olmaz.
    func loadPersisted() async -> [LogEntry] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: persistence?.loadEntries() ?? [])
            }
        }
    }

    /// Diskteki geçmişten bir SAYFA okur (en yeniden geriye; bkz. `FilePersistence.loadEntriesPage`).
    func loadPersistedPage(before cursor: String?, minimumEntries: Int) async -> PersistedLogPage {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let page = persistence?.loadEntriesPage(before: cursor, minimumEntries: minimumEntries)
                continuation.resume(returning: page ?? PersistedLogPage(entries: [], nextCursor: nil))
            }
        }
    }

    /// Diskteki kayıtları birleştirip paylaşılabilir .log dosyası üretir (asenkron, bloke etmez).
    func exportFileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: persistence?.consolidatedTextURL(using: exportFormatter))
            }
        }
    }

    /// Verilen kayıtları (ör. viewer'da o an **filtreli** görünen liste) paylaşılabilir .log
    /// dosyasına yazar. Disk persistance'tan bağımsız — yalnız geçirilen kayıtları dışa aktarır.
    /// Metin oluşturma + dosya I/O serial kuyrukta yapılır → çağıran bloke olmaz.
    func exportFileURL(entries: [LogEntry]) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let text = entries.map { exportFormatter.string(from: $0) }.joined(separator: "\n")
                continuation.resume(returning: LogExportFile.write(text))
            }
        }
    }

    /// Verilen kayıtları **ham NDJSON** (satır başına bir JSON `LogEntry`) dosyasına yazar.
    /// Disk formatıyla birebir aynı şema → jq/backend analizi/başka araçlara kayıpsız beslenebilir.
    func exportNDJSONFileURL(entries: [LogEntry]) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.withoutEscapingSlashes]
                let text = entries
                    .compactMap { entry in
                        (try? encoder.encode(entry)).flatMap { String(data: $0, encoding: .utf8) }
                    }
                    .joined(separator: "\n")
                continuation.resume(returning: LogExportFile.write(text, fileExtension: "ndjson"))
            }
        }
    }
}

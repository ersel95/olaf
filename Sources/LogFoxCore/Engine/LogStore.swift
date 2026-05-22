import Foundation

/// LogFox'un çekirdek deposu: redaksiyon → in-memory ring buffer → (ops.) disk → canlı yayın.
///
/// Tüm mutasyon tek bir serial kuyrukta yapılır → kayıt sırası deterministiktir ve
/// veri yarışı yoktur. `@unchecked Sendable` bu serial-kuyruk sözleşmesine dayanır.
final class LogStore: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.logfox.store", qos: .utility)
    private let capacity: Int
    private let redactor: any Redactor
    private let persistence: FilePersistence?
    private let exportFormatter: any LogFormatter
    private let osLogMirror: OSLogMirror?

    /// Sabit kapasiteli halka tampon (en yeni `capacity` kayıt).
    private var buffer: [LogEntry] = []
    /// Canlı dinleyiciler (viewer). Kuyrukta erişilir.
    private var continuations: [UUID: AsyncStream<LogEntry>.Continuation] = [:]

    init(
        capacity: Int,
        redactor: any Redactor,
        persistence: FilePersistence?,
        exportFormatter: any LogFormatter,
        osLogMirror: OSLogMirror?
    ) {
        self.capacity = capacity
        self.redactor = redactor
        self.persistence = persistence
        self.exportFormatter = exportFormatter
        self.osLogMirror = osLogMirror
        self.buffer.reserveCapacity(capacity)
    }

    // MARK: - Yazma

    /// Ham (redakte edilmemiş) veriyi alır; redaksiyon kuyruk içinde yapılır.
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
                message: redactor.redact(rawMessage),
                metadata: redactor.redact(metadata: rawMetadata),
                file: file,
                line: line,
                function: function,
                thread: thread
            )

            buffer.append(entry)
            if buffer.count > capacity {
                buffer.removeFirst(buffer.count - capacity)
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
        queue.sync { buffer }
    }

    /// Yeni kayıtları canlı yayınlayan akış. Viewer abone olur.
    func makeStream() -> AsyncStream<LogEntry> {
        AsyncStream { continuation in
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
            buffer.removeAll(keepingCapacity: true)
            persistence?.clear()
        }
    }

    /// Diskteki tüm kayıtları (oturumlar arası geçmiş dahil) ayrıştırıp döndürür.
    func loadPersisted() -> [LogEntry] {
        queue.sync { persistence?.loadEntries() ?? [] }
    }

    func exportFileURL() -> URL? {
        queue.sync { persistence?.consolidatedTextURL(using: exportFormatter) }
    }
}

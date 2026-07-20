import Foundation

/// Olaf's core store: in-memory ring buffer → (optionally) disk → live broadcast.
///
/// All mutation happens on a single serial queue → entry ordering is deterministic and there
/// are no data races. `@unchecked Sendable` relies on this serial-queue contract.
final class LogStore: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.olaf.store", qos: .utility)
    private let capacity: Int
    private let persistence: FilePersistence?
    private let exportFormatter: any LogFormatter
    private let osLogMirror: OSLogMirror?
    private let sessionID: String

    /// Fixed-capacity ring buffer (the newest `capacity` entries).
    /// `ring` grows until it reaches capacity; once full, the entry at `head` (the oldest) is
    /// overwritten. Append + evict are **O(1)** (instead of the O(n) shift from `Array.removeFirst`).
    private var ring: [LogEntry] = []
    /// Index of the oldest entry within `ring` once the buffer is full.
    private var head = 0
    /// Live listeners (the viewer). Accessed on the queue.
    private var continuations: [UUID: AsyncStream<LogEntry>.Continuation] = [:]

    /// The buffer's entries (oldest to newest), called from within the queue.
    private var orderedBuffer: [LogEntry] {
        if ring.count < capacity { return ring }   // if not yet full, head == 0, insertion order is preserved
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

    // MARK: - Writing

    /// Takes data from the call site and writes it to the buffer/disk on the serial queue.
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
                ring[head] = entry            // overwrite the oldest entry
                head = (head + 1) % capacity  // O(1) evict
            }

            persistence?.write(entry)
            osLogMirror?.log(entry)

            for continuation in continuations.values {
                continuation.yield(entry)
            }
        }
    }

    // MARK: - Reading

    /// An instant copy of all entries currently in the buffer (oldest to newest).
    func snapshot() -> [LogEntry] {
        queue.sync { orderedBuffer }
    }

    /// Non-blocking version of `snapshot()`: so the caller (e.g. the main thread) doesn't wait on
    /// `queue.sync` while the `.utility` queue is processing a heavy write burst.
    func snapshotAsync() async -> [LogEntry] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: orderedBuffer)
            }
        }
    }

    /// A stream that live-broadcasts new entries. The viewer subscribes to it.
    func makeStream() -> AsyncStream<LogEntry> {
        // Bounded buffer: so memory doesn't grow unbounded if the viewer is slow (or paused) —
        // the newest `capacity` entries are kept, older ones are dropped (the buffer already shows the newest).
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

    // MARK: - Management

    func clear() {
        queue.async { [self] in
            ring.removeAll(keepingCapacity: true)
            head = 0
            persistence?.clear()
        }
    }

    /// Parses all entries on disk (including cross-session history) ASYNCHRONOUSLY.
    /// Heavy file I/O happens on the serial queue → the caller (e.g. the main thread) is not blocked.
    func loadPersisted() async -> [LogEntry] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: persistence?.loadEntries() ?? [])
            }
        }
    }

    /// Reads a PAGE from on-disk history (newest to oldest; see `FilePersistence.loadEntriesPage`).
    func loadPersistedPage(before cursor: String?, minimumEntries: Int) async -> PersistedLogPage {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let page = persistence?.loadEntriesPage(before: cursor, minimumEntries: minimumEntries)
                continuation.resume(returning: page ?? PersistedLogPage(entries: [], nextCursor: nil))
            }
        }
    }

    /// Merges the on-disk entries and produces a shareable .log file (async, non-blocking).
    func exportFileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: persistence?.consolidatedTextURL(using: exportFormatter))
            }
        }
    }

    /// Writes the given entries (e.g. the currently **filtered** list in the viewer) to a
    /// shareable .log file. Independent of disk persistence — exports only the passed-in entries.
    /// Text generation + file I/O happen on the serial queue → the caller is not blocked.
    func exportFileURL(entries: [LogEntry]) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let text = entries.map { exportFormatter.string(from: $0) }.joined(separator: "\n")
                continuation.resume(returning: LogExportFile.write(text))
            }
        }
    }

    /// Writes the given entries to a **raw NDJSON** (one JSON `LogEntry` per line) file.
    /// Identical schema to the on-disk format → can be fed losslessly into jq/backend analysis/other tools.
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

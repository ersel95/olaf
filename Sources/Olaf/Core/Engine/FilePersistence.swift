import Foundation

/// Writes logs to disk as **NDJSON** (one JSON `LogEntry` per line); applies size-based
/// rotation and file-count retention. Thanks to NDJSON, entries can be read back with full
/// fidelity (cross-session history). Export, on the other hand, converts to human-readable plain text.
///
/// This type is **not thread-safe on its own**; it is only ever called from `LogStore`'s serial
/// queue. `@unchecked Sendable` relies on this contract.
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
    /// Monotonic counter to prevent file-name collisions (→ log loss) when multiple rotations
    /// happen within the same second. Incremented on the serial queue, so there's no race.
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

    // MARK: - Writing

    func write(_ entry: LogEntry) {
        guard let handle, let json = try? encoder.encode(entry) else { return }
        var data = json
        data.append(0x0A) // '\n'
        do {
            // The handle is positioned at the end on open (and on rotate); since there's a single
            // writer, the pointer stays at the end → a `seekToEnd()` syscall on every write is
            // unnecessary and has been removed.
            try handle.write(contentsOf: data)
            currentSize += data.count
            if currentSize >= maxFileSize {
                rotate()
            }
        } catch {
            // A disk error must not crash logging; fail silently.
        }
    }

    // MARK: - Reading (cross-session history)

    /// Parses and returns all entries on disk (oldest to newest). Corrupted lines are skipped.
    func loadEntries() -> [LogEntry] {
        try? handle?.synchronize()
        return (rotatedFilesSortedAscending() + [activeFileURL]).flatMap(decodeFile)
    }

    /// Reads on-disk history **paginated** — from the newest files backwards. The page unit is a
    /// file: whole files are added until `minimumEntries` is reached (or files run out); files are
    /// never split (since a file is capped at `maxFileSize`, page size is bounded).
    ///
    /// The cursor is the name of the file where the NEXT page will start (fixed at the time this
    /// page is produced). This way, even if the active file rotates between pages, no entry is
    /// duplicated: newly rotated files are newer than the cursor and thus out of scope. If the
    /// cursor's file has since been deleted (pruned), we fall back to the lexicographically oldest
    /// file preceding it (file names use a fixed-width timestamp → lexicographic order is chronological).
    func loadEntriesPage(before cursorFileName: String?, minimumEntries: Int) -> PersistedLogPage {
        try? handle?.synchronize()
        // Newest to oldest: active file + rotated files (reversed).
        let files = [activeFileURL] + rotatedFilesSortedAscending().reversed()

        let startIndex: Int
        if let cursorFileName {
            if let exact = files.firstIndex(where: { $0.lastPathComponent == cursorFileName }) {
                startIndex = exact
            } else {
                startIndex = files.firstIndex(where: {
                    $0.lastPathComponent != activeFileName && $0.lastPathComponent < cursorFileName
                }) ?? files.count
            }
        } else {
            startIndex = 0
        }

        var consumed: [[LogEntry]] = []
        var total = 0
        var index = startIndex
        while index < files.count, total < max(1, minimumEntries) {
            let decoded = decodeFile(files[index])
            consumed.append(decoded)
            total += decoded.count
            index += 1
        }

        return PersistedLogPage(
            // Files were consumed newest to oldest; the page content is returned oldest to newest.
            entries: consumed.reversed().flatMap { $0 },
            nextCursor: index < files.count ? files[index].lastPathComponent : nil
        )
    }

    /// Parses a single NDJSON file (oldest to newest). Corrupted lines are skipped.
    /// Splitting the data on `\n` (0x0A) avoids the cost of converting lines to `String` and
    /// re-encoding to UTF-8 (a double conversion).
    private func decodeFile(_ file: URL) -> [LogEntry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return data.split(separator: 0x0A, omittingEmptySubsequences: true).compactMap {
            try? decoder.decode(LogEntry.self, from: $0)
        }
    }

    // MARK: - Clearing & export

    func clear() {
        try? handle?.close()
        handle = nil
        for url in allLogFiles() {
            try? fileManager.removeItem(at: url)
        }
        try? openActiveFile()
    }

    /// Converts all entries on disk into a **human-readable plain-text** file using the given
    /// formatter, and returns a shareable URL.
    func consolidatedTextURL(using formatter: any LogFormatter) -> URL? {
        let text = loadEntries().map { formatter.string(from: $0) }.joined(separator: "\n")
        return LogExportFile.write(text, fileManager: fileManager)
    }

    // MARK: - Internal

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
        // Second (fixed width) + monotonic counter → many rotations within the same second don't collide.
        var rotatedURL = directory.appendingPathComponent(
            String(format: "\(rotatedPrefix)%010d-%06d.\(fileExtension)", stamp, rotationCounter)
        )
        // If the process restarts and rotates within the same second (counter reset), still ensure uniqueness.
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

    /// Deletes the oldest rotated files that exceed `maxFileCount` (excluding the active file).
    private func pruneOldFiles() {
        let rotated = rotatedFilesSortedAscending()
        // The active file also counts → at most (maxFileCount - 1) rotated files are kept.
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
            // Primarily creation date (correct chronological order independent of naming scheme), then name on ties.
            .sorted { lhs, rhs in
                let lDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                let rDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                if let lDate, let rDate, lDate != rDate { return lDate < rDate }
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
    }

    private func applyProtection(to url: URL) {
        // Encrypted until first unlock; banking-grade baseline protection.
        // `FileProtectionType` is only available on iOS/iPadOS (a no-op in the macOS test build).
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}

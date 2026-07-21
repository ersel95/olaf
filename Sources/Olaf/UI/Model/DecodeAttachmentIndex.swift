import Foundation

/// Folds `.decoding` entries into the network entry they belong to (same host+path,
/// nearest in time) so the list shows one badged network row instead of N decode rows.
/// Decode entries without a resolvable `url`, or with no network entry nearby, stay
/// unattached and keep rendering as regular rows (nothing is ever silently dropped).
struct DecodeAttachmentIndex: Sendable {
    /// Network entry id → its decode-error entries (chronological).
    let byNetworkID: [UUID: [LogEntry]]
    /// IDs of decoding entries that were attached (hidden from the flat list).
    let attachedIDs: Set<UUID>

    static let empty = DecodeAttachmentIndex(byNetworkID: [:], attachedIDs: [])

    /// Max time distance between a decode entry and the network call it decodes.
    /// Decode runs right after the response completes; 30 s comfortably covers
    /// queue hops while keeping repeats of the same endpoint from cross-matching.
    static let attachWindow: TimeInterval = 30

    func errors(for entry: LogEntry) -> [LogEntry] {
        byNetworkID[entry.id] ?? []
    }

    static func build(from entries: [LogEntry]) -> DecodeAttachmentIndex {
        var networkByKey: [String: [(id: UUID, date: Date)]] = [:]
        for entry in entries where entry.category == .network {
            guard let url = entry.metadata["url"], let key = endpointKey(url) else { continue }
            networkByKey[key, default: []].append((entry.id, entry.date))
        }
        guard !networkByKey.isEmpty else { return .empty }

        var byNetworkID: [UUID: [LogEntry]] = [:]
        var attachedIDs = Set<UUID>()
        for entry in entries where entry.category == .decoding {
            guard let url = entry.metadata["url"],
                  let key = endpointKey(url),
                  let candidates = networkByKey[key],
                  let nearest = candidates.min(by: {
                      abs($0.date.timeIntervalSince(entry.date)) < abs($1.date.timeIntervalSince(entry.date))
                  }),
                  abs(nearest.date.timeIntervalSince(entry.date)) <= attachWindow
            else { continue }
            byNetworkID[nearest.id, default: []].append(entry)
            attachedIDs.insert(entry.id)
        }
        return DecodeAttachmentIndex(byNetworkID: byNetworkID, attachedIDs: attachedIDs)
    }

    /// `"https://host/path?query"` → `"host/path"`. Scheme and query are ignored:
    /// the network side logs the full URL with query, while decode reporters
    /// absolutize a bare path — both must land on the same key.
    static func endpointKey(_ url: String) -> String? {
        guard let comps = URLComponents(string: url) else { return nil }
        var path = comps.path
        if path.hasSuffix("/") { path = String(path.dropLast()) }
        guard let host = comps.host else { return path.isEmpty ? nil : path }
        return host + path
    }
}

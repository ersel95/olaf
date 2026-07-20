import Foundation

/// An in-flight (not yet completed) network capture.
public struct PendingNetworkRequest: Identifiable, Sendable {
    public let id: UUID
    public let method: String
    public let url: String
    public let startDate: Date

    /// Elapsed time since start (seconds).
    public var elapsedSeconds: Int {
        max(0, Int(Date().timeIntervalSince(startDate)))
    }
}

/// Lock-protected registry of in-flight captures. `OlafURLProtocol` registers a request when it
/// starts, and drops it on completion (success/error/cancel). Feeds the viewer's "Active requests"
/// section — a snapshot is read on a 1s `TimelineView` tick; no separate broadcast mechanism needed.
final class PendingRequestRegistry: @unchecked Sendable {

    static let shared = PendingRequestRegistry()

    private let lock = NSLock()
    private var items: [UUID: PendingNetworkRequest] = [:]

    func register(method: String, url: String) -> UUID {
        let request = PendingNetworkRequest(id: UUID(), method: method, url: url, startDate: Date())
        lock.lock(); items[request.id] = request; lock.unlock()
        return request.id
    }

    func unregister(_ id: UUID) {
        lock.lock(); items[id] = nil; lock.unlock()
    }

    /// Snapshot sorted by start time (oldest first).
    var snapshot: [PendingNetworkRequest] {
        lock.lock(); defer { lock.unlock() }
        return items.values.sorted { $0.startDate < $1.startDate }
    }

    /// For test isolation: drops all entries.
    func removeAll() {
        lock.lock(); items.removeAll(); lock.unlock()
    }
}

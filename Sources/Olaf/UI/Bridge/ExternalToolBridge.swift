import Foundation

/// Represents a transition from the Olaf viewer to another diagnostic tool.
///
/// The package is **not** tied to any external tool: the app conforms its own bridge to this
/// protocol and registers it with `OlafUI.register(_:)`. No button appears in the viewer if no
/// bridge is registered.
public protocol ExternalToolBridge: Sendable {
    /// Title shown in the viewer toolbar.
    var title: String { get }
    /// System symbol name (SF Symbol), optional.
    var systemImage: String? { get }
    /// Opens the tool. Closing the Olaf viewer is the caller's responsibility (usually dismiss first).
    @MainActor func open()
}

public extension ExternalToolBridge {
    var systemImage: String? { nil }
}

/// Process-wide registry of registered external tool bridges. Thread-safe.
final class ExternalToolRegistry: @unchecked Sendable {

    static let shared = ExternalToolRegistry()

    private let lock = NSLock()
    private var bridges: [any ExternalToolBridge] = []

    func register(_ bridge: any ExternalToolBridge) {
        lock.lock(); defer { lock.unlock() }
        bridges.append(bridge)
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        bridges.removeAll()
    }

    var all: [any ExternalToolBridge] {
        lock.lock(); defer { lock.unlock() }
        return bridges
    }
}

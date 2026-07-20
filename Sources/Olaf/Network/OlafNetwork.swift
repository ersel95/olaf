import Foundation

/// Olaf network capture facade. Captures the app's network requests and logs them to Olaf
/// **raw** (unredacted) under the `.network` category.
///
/// ```swift
/// // To capture all requests (Alamofire/URLSession custom config):
/// OlafNetwork.install(into: sessionConfiguration)
///
/// // To work TOGETHER with another capture tool, chain it:
/// OlafNetwork.install(into: sessionConfiguration, chainingTo: [OtherCaptureProtocol.self])
/// ```
public enum OlafNetwork {

    private static let box = ConfigBox()

    /// Active configuration. Can be set before/after `Olaf.start`.
    public static var configuration: OlafNetworkConfiguration {
        get { box.value }
        set { box.value = newValue }
    }

    /// Additional `URLProtocol` classes to add to Olaf's own (uncaptured) proxy session when it
    /// restarts a request. Used so other capture tools can also capture the traffic.
    public static var chainedProtocolClasses: [AnyClass] {
        get { box.chained }
        set { box.chained = newValue }
    }

    /// Injects the capture protocol into the given `URLSessionConfiguration` and sets the capture
    /// parameters **at init**.
    /// - Parameters:
    ///   - configuration: The session config the protocol will be prepended to.
    ///   - networkConfiguration: Capture filters (body/header capture on by default).
    ///   - chainingTo: Additional `URLProtocol`s the request should pass through after Olaf
    ///     captures it — so another capture tool also sees the same traffic.
    public static func install(
        into configuration: URLSessionConfiguration,
        with networkConfiguration: OlafNetworkConfiguration = .default,
        chainingTo chainedClasses: [AnyClass] = []
    ) {
        self.configuration = networkConfiguration
        self.chainedProtocolClasses = chainedClasses
        // Remove any existing copies, then guarantee we're prepended first (URLProtocol: "first match wins").
        let id = ObjectIdentifier(OlafURLProtocol.self)
        var classes = (configuration.protocolClasses ?? []).filter { ObjectIdentifier($0) != id }
        classes.insert(OlafURLProtocol.self, at: 0)
        configuration.protocolClasses = classes
    }

    /// Registers the protocol for `URLSession.shared` and global requests, and sets the capture parameters at init.
    public static func installGlobally(
        _ networkConfiguration: OlafNetworkConfiguration = .default,
        chainingTo chainedClasses: [AnyClass] = []
    ) {
        self.configuration = networkConfiguration
        self.chainedProtocolClasses = chainedClasses
        URLProtocol.registerClass(OlafURLProtocol.self)
    }

    /// **Easiest setup — WITHOUT touching the host's networking code.**
    /// Swizzles `URLSessionConfiguration.default/.ephemeral` so it's automatically injected into
    /// every session (including Alamofire) + registers globally for the shared session.
    ///
    /// SSL: the proxy session uses **default system validation** (pinning/OS trust is not bypassed);
    /// for custom enterprise CAs use `allowsArbitraryServerTrustForCapture` (non-prod only). For **non-prod debug** use only.
    ///
    /// ```swift
    /// // One line inside OlafManager.initialize() — no need to touch BaseService:
    /// OlafNetwork.startAutomaticCapture()
    /// ```
    public static func startAutomaticCapture(_ networkConfiguration: OlafNetworkConfiguration = .default) {
        self.configuration = networkConfiguration
        URLSessionConfiguration.olafEnableAutomaticInjection()
        URLProtocol.registerClass(OlafURLProtocol.self)
    }

    /// Removes the global registration.
    public static func uninstallGlobally() {
        URLProtocol.unregisterClass(OlafURLProtocol.self)
    }

    /// Protocol class for manual injection.
    public static var protocolClass: AnyClass { OlafURLProtocol.self }

    /// Currently in-flight (not yet completed) captures — oldest first.
    /// The viewer's "Active requests" section polls this periodically; stuck requests show up here.
    public static var pendingRequests: [PendingNetworkRequest] {
        PendingRequestRegistry.shared.snapshot
    }

    // MARK: - Response mocking

    /// Registers a mock. Matching requests receive this response **without hitting the network**
    /// (capture must be active — `startAutomaticCapture`/`install`). If multiple mocks match, the
    /// first one added wins. Non-prod debug only (like the rest of Olaf, should stay under `#if !PROD`).
    public static func addMock(_ mock: OlafMockResponse) {
        box.mocks.append(mock)
    }

    /// Removes a single mock (used by the viewer's mock list).
    public static func removeMock(id: UUID) {
        box.mocks.removeAll { $0.id == id }
    }

    /// Removes all mocks (requests go to the real backend again).
    public static func removeAllMocks() {
        box.mocks = []
    }

    /// Registered mocks (in insertion order).
    public static var activeMocks: [OlafMockResponse] {
        box.mocks
    }

    /// The first mock matching the given request (internal — used by `OlafURLProtocol`).
    static func mock(for request: URLRequest) -> OlafMockResponse? {
        let mocks = box.mocks
        guard !mocks.isEmpty else { return nil }
        return mocks.first { $0.matches(request) }
    }

    // Internal access (read by URLProtocol's config).
    static var current: OlafNetworkConfiguration { box.value }

    private final class ConfigBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = OlafNetworkConfiguration.default
        private var _chained: [AnyClass] = []
        private var _mocks: [OlafMockResponse] = []

        var value: OlafNetworkConfiguration {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
        var chained: [AnyClass] {
            get { lock.lock(); defer { lock.unlock() }; return _chained }
            set { lock.lock(); _chained = newValue; lock.unlock() }
        }
        var mocks: [OlafMockResponse] {
            get { lock.lock(); defer { lock.unlock() }; return _mocks }
            set { lock.lock(); _mocks = newValue; lock.unlock() }
        }
    }
}

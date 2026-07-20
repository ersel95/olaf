//  OlafIntegration.swift
//
//  DROP-IN TEMPLATE — NOT part of the Olaf package (outside Sources/, not compiled by SPM).
//  Copy this into the host app (e.g. Core/Utils/); adapt the `// ADAPT:` spots to your project.
//
//  • Starts Olaf from a single point,
//  • captures network traffic (OlafNetwork),
//  • sets up shake → viewer.
//
//  Single product: `Olaf` (engine + network capture + viewer all included).

import Foundation
@_exported import Olaf

// MARK: - App-specific log categories

public extension LogCategory {
    // ADAPT: adjust to match your project's modules.
    static let cards: LogCategory = "cards"
    static let accounts: LogCategory = "accounts"
    static let transfers: LogCategory = "transfers"
}

// MARK: - Integration manager

public final class OlafManager {

    public static let shared = OlafManager()
    private init() {}

    /// Starts Olaf. Must be called BEFORE the shared URLSession is set up (capture swizzling before the session).
    public func initialize() {
        // ADAPT: keep this off in prod. Recommended: a compile-time boundary (capture code doesn't end up in the prod binary).
        // Alternative: a runtime feature flag (capture code stays in the binary, disabled at runtime).
        #if !PROD
        Olaf.start(.default)

        // Automatically injects into all sessions (without touching the host's networking code, without breaking SSL).
        // Note: if you set up your own custom Alamofire/URLSession config, use configureNetworkCapture instead.
        OlafNetwork.startAutomaticCapture(Self.networkConfiguration)

        Task { @MainActor in
            OlafUI.install()
        }
        #endif
    }

    // MARK: - Network capture configuration

    /// Shared network-capture setting (used by both `startAutomaticCapture` and `configureNetworkCapture`).
    ///
    /// ADAPT: `allowsArbitraryServerTrustForCapture` — enable this if your internal/UAT gateway presents a
    /// certificate signed by a **private corporate CA**. Because the capture proxy does NOT share the host's
    /// trust delegate, default validation yields TLS `-9807` / NSURLError `-1202` ("certificate invalid"). This
    /// flag only relaxes the **capture proxy's** server-trust check (your app's own traffic validation is
    /// unchanged, SSL is not broken). The code already compiles under `#if !PROD` → it doesn't end up in the
    /// prod binary. Not needed for public certificates signed by a system CA; leave it `false`.
    private static let networkConfiguration = OlafNetworkConfiguration(
        allowsArbitraryServerTrustForCapture: false
    )

    /// (Optional) If the host sets up its own `URLSessionConfiguration`: injects Olaf at the front of this
    /// config instead of automatic swizzling. If you use this, startAutomaticCapture in initialize is not needed.
    public func configureNetworkCapture(_ configuration: URLSessionConfiguration) {
        #if !PROD
        OlafNetwork.install(into: configuration, with: Self.networkConfiguration)
        #endif
    }

    // MARK: - Logging (the app logs through this manager)
    // DO NOT touch the file/line/function defaults — they capture the call site automatically.

    public func trace(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        Olaf.trace(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func debug(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        Olaf.debug(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func info(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        Olaf.info(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func notice(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        Olaf.notice(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func warning(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        Olaf.warning(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func error(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        Olaf.error(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func error(_ error: Error, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        Olaf.error(error, category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func critical(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        Olaf.critical(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }
}

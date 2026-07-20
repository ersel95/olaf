//  OlafLogHandler.swift
//
//  DROP-IN TEMPLATE — NOT part of the Olaf package (outside Sources/, not compiled by SPM).
//  A bridge for hosts using swift-log: after `LoggingSystem.bootstrap`, ALL `Logging.Logger`
//  calls in the app and its dependencies flow into Olaf (the Logger's label → category).
//
//  Olaf deliberately carries ZERO dependencies (and is a single SPM product) → no package
//  dependency on swift-log is added; copy this file into the host app.
//
//  Requirement: the host project has a swift-log dependency (https://github.com/apple/swift-log).
//
//  Setup (once, at app startup, AFTER `Olaf.start`):
//      LoggingSystem.bootstrap { label in OlafLogHandler(label: label) }
//
//  To use alongside other backends:
//      LoggingSystem.bootstrap { label in
//          MultiplexLogHandler([
//              OlafLogHandler(label: label),
//              StreamLogHandler.standardOutput(label: label)
//          ])
//      }

import Foundation
import Logging
import Olaf

public struct OlafLogHandler: LogHandler {

    /// The swift-log Logger label — used as the Olaf category.
    private let label: String

    public var logLevel: Logging.Logger.Level = .trace
    public var metadata: Logging.Logger.Metadata = [:]

    public init(label: String) {
        self.label = label
    }

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata explicitMetadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // The handler's metadata + the call's metadata are merged (the call takes priority), flattened to strings.
        var merged = self.metadata
        if let explicitMetadata {
            merged.merge(explicitMetadata) { _, explicit in explicit }
        }
        var flattened = merged.mapValues { "\($0)" }
        flattened["source"] = source

        Olaf.log(
            Self.mapLevel(level),
            message.description,
            category: LogCategory(label),
            metadata: flattened,
            file: file,
            line: Int(line),
            function: function
        )
    }

    /// swift-log → Olaf level mapping (one-to-one).
    private static func mapLevel(_ level: Logging.Logger.Level) -> LogLevel {
        switch level {
        case .trace: return .trace
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }
}

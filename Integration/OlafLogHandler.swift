//  OlafLogHandler.swift
//
//  DROP-IN TEMPLATE — Olaf paketinin parçası DEĞİLDİR (Sources/ dışında, SPM derlemez).
//  swift-log kullanan host'lar için köprü: `LoggingSystem.bootstrap` sonrası uygulamadaki ve
//  bağımlılıklardaki TÜM `Logging.Logger` çağrıları Olaf'a akar (Logger label'ı → kategori).
//
//  Olaf bilinçli olarak SIFIR bağımlılık taşır (ve tek SPM ürünüdür) → swift-log'a paket
//  bağımlılığı eklenmez; bu dosyayı host uygulamaya kopyalayın.
//
//  Gereksinim: host projede swift-log bağımlılığı (https://github.com/apple/swift-log).
//
//  Kurulum (uygulama başlangıcında, `Olaf.start` SONRASI, bir kez):
//      LoggingSystem.bootstrap { label in OlafLogHandler(label: label) }
//
//  Başka backend'lerle birlikte kullanmak için:
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

    /// swift-log Logger etiketi — Olaf kategorisi olarak kullanılır.
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
        // Handler metadata'sı + çağrı metadata'sı birleştirilir (çağrı önceliklidir), string'e düzlenir.
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

    /// swift-log → Olaf seviye eşlemesi (birebir).
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

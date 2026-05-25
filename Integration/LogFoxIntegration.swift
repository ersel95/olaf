//  LogFoxIntegration.swift
//
//  DROP-IN TEMPLATE — LogFox paketinin parçası DEĞİLDİR (Sources/ dışında, SPM derlemez).
//  Host uygulamaya (örn. Core/Utils/) kopyalayın; `// ADAPT:` yerlerini projeye uyarlayın.
//
//  • LogFox'u tek noktadan başlatır,
//  • `network: .netfox / .none` ile Netfox'u açıp kapatır,
//  • Netfox köprüsü pakettedir (LogFoxNetfox ürünü) — host'ta köprü tanımı / `import netfox` GEREKMEZ.
//
//  Ürün seçimi: LogFoxCore + LogFoxUI zorunlu; ağ yakalama için LogFoxNetwork; Netfox için LogFoxNetfox.

import Foundation
@_exported import LogFoxCore
import LogFoxUI
#if canImport(LogFoxNetwork)
import LogFoxNetwork
#endif
#if canImport(LogFoxNetfox)
import LogFoxNetfox
#endif

// MARK: - App'e özel log kategorileri

public extension LogCategory {
    // ADAPT: projenizin modüllerine göre düzenleyin.
    static let cards: LogCategory = "cards"
    static let accounts: LogCategory = "accounts"
    static let transfers: LogCategory = "transfers"
}

// MARK: - Network logger seçimi

/// `.netfox` → Netfox başlatılır ve viewer'a köprü eklenir (LogFoxNetfox ürünü gerekir); `.none` → yalnız LogFox.
public enum LogFoxNetworkLogger {
    case netfox
    case none
}

// MARK: - Entegrasyon yöneticisi

public final class LogFoxManager {

    public static let shared = LogFoxManager()
    private init() {}

    private var activeNetwork: LogFoxNetworkLogger = .none

    /// LogFox'u başlatır. Paylaşılan URLSession kurulmadan ÖNCE çağrılmalı (capture swizzle'ı session'dan önce).
    public func initialize(network: LogFoxNetworkLogger = .none) {
        // ADAPT: prod'da kapalı tutun. Önerilen: derleme sınırı (capture kodu prod binary'sine girmez).
        // Alternatif: runtime feature flag (capture kodu binary'de kalır, çalışma-zamanı kapalı).
        #if !PROD
        activeNetwork = network

        LogFox.start(.bankingDefault)

        #if canImport(LogFoxNetwork)
        // Tüm session'lara otomatik enjekte (host networking koduna dokunmadan, SSL kırmadan).
        // Not: Kendi özel Alamofire/URLSession config'inizi kuruyorsanız bunun yerine configureNetworkCapture'ı kullanın.
        LogFoxNetwork.startAutomaticCapture()
        #endif

        if network == .netfox {
            #if canImport(LogFoxNetfox)
            LogFoxNetfox.startCapture()
            #endif
        }

        Task { @MainActor in
            LogFoxUI.install()
            if network == .netfox {
                #if canImport(LogFoxNetfox)
                LogFoxNetfox.install()
                #endif
            }
        }
        #endif
    }

    /// (Opsiyonel) Host kendi `URLSessionConfiguration`'ını kuruyorsa: otomatik swizzle yerine bu config'e
    /// LogFox'u en öne enjekte eder ve `.netfox` modunda Netfox'a zincirler (ikisi de yakalar).
    /// Bunu kullanıyorsanız initialize içindeki startAutomaticCapture'a gerek yoktur.
    public func configureNetworkCapture(_ configuration: URLSessionConfiguration) {
        #if !PROD
        #if canImport(LogFoxNetwork)
        var chain: [AnyClass] = []
        if activeNetwork == .netfox {
            #if canImport(LogFoxNetfox)
            chain = LogFoxNetfox.chainProtocolClasses
            #endif
        }
        LogFoxNetwork.install(into: configuration, chainingTo: chain)
        #endif
        #endif
    }

    // MARK: - Logging (app bu manager üzerinden loglar)
    // file/line/function default'larına DOKUNMA — çağrı yerini otomatik yakalar.

    public func trace(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        LogFox.trace(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func debug(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        LogFox.debug(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func info(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        LogFox.info(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func notice(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        LogFox.notice(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func warning(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        LogFox.warning(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func error(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        LogFox.error(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func error(_ error: Error, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        LogFox.error(error, category: category, metadata: metadata, file: file, line: line, function: function)
    }

    public func critical(_ message: @autoclosure () -> String, category: LogCategory = .general, metadata: [String: String] = [:], file: String = #fileID, line: Int = #line, function: String = #function) {
        LogFox.critical(message(), category: category, metadata: metadata, file: file, line: line, function: function)
    }
}

//  OlafIntegration.swift
//
//  DROP-IN TEMPLATE — Olaf paketinin parçası DEĞİLDİR (Sources/ dışında, SPM derlemez).
//  Host uygulamaya (örn. Core/Utils/) kopyalayın; `// ADAPT:` yerlerini projeye uyarlayın.
//
//  • Olaf'u tek noktadan başlatır,
//  • network trafiğini yakalar (OlafNetwork),
//  • shake → viewer kurar.
//
//  Tek ürün: `Olaf` (motor + network capture + viewer birlikte gelir).

import Foundation
@_exported import Olaf

// MARK: - App'e özel log kategorileri

public extension LogCategory {
    // ADAPT: projenizin modüllerine göre düzenleyin.
    static let cards: LogCategory = "cards"
    static let accounts: LogCategory = "accounts"
    static let transfers: LogCategory = "transfers"
}

// MARK: - Entegrasyon yöneticisi

public final class OlafManager {

    public static let shared = OlafManager()
    private init() {}

    /// Olaf'u başlatır. Paylaşılan URLSession kurulmadan ÖNCE çağrılmalı (capture swizzle'ı session'dan önce).
    public func initialize() {
        // ADAPT: prod'da kapalı tutun. Önerilen: derleme sınırı (capture kodu prod binary'sine girmez).
        // Alternatif: runtime feature flag (capture kodu binary'de kalır, çalışma-zamanı kapalı).
        #if !PROD
        Olaf.start(.default)

        // Tüm session'lara otomatik enjekte (host networking koduna dokunmadan, SSL kırmadan).
        // Not: Kendi özel Alamofire/URLSession config'inizi kuruyorsanız bunun yerine configureNetworkCapture'ı kullanın.
        OlafNetwork.startAutomaticCapture(Self.networkConfiguration)

        Task { @MainActor in
            OlafUI.install()
        }
        #endif
    }

    // MARK: - Network capture konfigürasyonu

    /// Ortak network-capture ayarı (hem `startAutomaticCapture` hem `configureNetworkCapture` kullanır).
    ///
    /// ADAPT: `allowsArbitraryServerTrustForCapture` — iç/UAT gateway'iniz **özel kurumsal CA** ile imzalı
    /// bir sertifika sunuyorsa açın. Capture proxy'si host'un trust delegate'ini PAYLAŞMADIĞI için default
    /// doğrulama TLS `-9807` / NSURLError `-1202` ("sertifika geçersiz") verir. Bu bayrak yalnız **capture
    /// proxy'sinin** server-trust'ını gevşetir (uygulamanızın kendi trafiğinin doğrulaması değişmez, SSL
    /// kırılmaz). Kod zaten `#if !PROD` altında derlenir → prod binary'sine girmez. Sistem CA'sıyla imzalı
    /// public sertifikalarda gerekmez; `false` bırakın.
    private static let networkConfiguration = OlafNetworkConfiguration(
        allowsArbitraryServerTrustForCapture: false
    )

    /// (Opsiyonel) Host kendi `URLSessionConfiguration`'ını kuruyorsa: otomatik swizzle yerine bu config'e
    /// Olaf'u en öne enjekte eder. Bunu kullanıyorsanız initialize içindeki startAutomaticCapture'a gerek yoktur.
    public func configureNetworkCapture(_ configuration: URLSessionConfiguration) {
        #if !PROD
        OlafNetwork.install(into: configuration, with: Self.networkConfiguration)
        #endif
    }

    // MARK: - Logging (app bu manager üzerinden loglar)
    // file/line/function default'larına DOKUNMA — çağrı yerini otomatik yakalar.

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

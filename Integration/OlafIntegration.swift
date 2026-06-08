//  OlafIntegration.swift
//
//  DROP-IN TEMPLATE — Olaf paketinin parçası DEĞİLDİR (Sources/ dışında, SPM derlemez).
//  Host uygulamaya (örn. Core/Utils/) kopyalayın; `// ADAPT:` yerlerini projeye uyarlayın.
//
//  • Olaf'u tek noktadan başlatır,
//  • (opsiyonel) OlafNetwork ile ağ trafiğini yakalar,
//  • shake → viewer kurar.
//
//  Ürün seçimi: OlafCore + OlafUI zorunlu; ağ yakalama için OlafNetwork.

import Foundation
@_exported import OlafCore
import OlafUI
#if canImport(OlafNetwork)
import OlafNetwork
#endif
#if canImport(OlafUpload)
import OlafUpload
#endif

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
        Olaf.start(.bankingDefault)

        #if canImport(OlafNetwork)
        // Tüm session'lara otomatik enjekte (host networking koduna dokunmadan, SSL kırmadan).
        // Not: Kendi özel Alamofire/URLSession config'inizi kuruyorsanız bunun yerine configureNetworkCapture'ı kullanın.
        OlafNetwork.startAutomaticCapture()
        #endif

        Task { @MainActor in
            OlafUI.install()
        }

        // OPT-IN bug-reporter (screenshot → banner → upload). VARSAYILAN KAPALI.
        // `enabled: false` iken hiçbir remote config / detector / tracker / upload kodu çalışmaz
        // (shake → log görüntüleme bundan bağımsız, etkilenmez).
        //
        // Açmak için: `enabled: true` + appKey/apiKey/baseURL'i HOST tarafından (xcconfig/secrets)
        // sağlayın — repo'ya ASLA commit etmeyin (public repo). Aşağıdaki erişimcileri kendi
        // güvenli kaynağınıza (Info.plist'e xcconfig'ten enjekte edilen değer vb.) bağlayın.
        #if canImport(OlafUpload)
        if let baseURL = Self.olafUploadBaseURL {
            OlafUpload.configure(
                enabled: Self.bugReporterEnabled,      // ADAPT: build-time flag (default false önerilir)
                appKey: Self.olafAppKey,               // ADAPT: xcconfig/secrets'tan
                apiKey: Self.olafApiKey,               // ADAPT: xcconfig/secrets'tan
                baseURL: baseURL,                      // ADAPT: xcconfig/secrets'tan
                environment: Self.olafEnvironment      // ADAPT: "staging"/"uat" vb.
            )
        }
        #endif
        #endif
    }

    // MARK: - Bug-reporter konfig kaynakları (HOST sağlar — repoya commit edilmez)
    // ADAPT: Bu değerleri Info.plist'e xcconfig'ten enjekte edip burada okuyun. Hard-code ETMEYİN.

    /// Bug-reporter açık mı? Default `false` (opt-in). xcconfig/build flag'inden besleyin.
    private static var bugReporterEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "OLAF_BUG_REPORTER_ENABLED") as? String)?.lowercased() == "true"
    }
    private static var olafAppKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OLAF_APP_KEY") as? String ?? ""
    }
    private static var olafApiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OLAF_API_KEY") as? String ?? ""
    }
    private static var olafEnvironment: String {
        Bundle.main.object(forInfoDictionaryKey: "OLAF_ENVIRONMENT") as? String ?? "staging"
    }
    private static var olafUploadBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "OLAF_API_BASE_URL") as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// (Opsiyonel) Host kendi `URLSessionConfiguration`'ını kuruyorsa: otomatik swizzle yerine bu config'e
    /// Olaf'u en öne enjekte eder. Bunu kullanıyorsanız initialize içindeki startAutomaticCapture'a gerek yoktur.
    public func configureNetworkCapture(_ configuration: URLSessionConfiguration) {
        #if !PROD
        #if canImport(OlafNetwork)
        OlafNetwork.install(into: configuration)
        #endif
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

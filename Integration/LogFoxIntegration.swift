//  LogFoxIntegration.swift
//
//  DROP-IN TEMPLATE — bu dosya LogFox paketinin parçası DEĞİLDİR (Sources/ dışında, SPM derlemez).
//  Host uygulamaya (örn. Core/Utils/ altına) kopyalayın. `// ADAPT:` ile işaretli yerleri projeye uyarlayın.
//
//  Bu dosya:
//   • LogFox'u NetfoxManager paterniyle başlatır,
//   • Projede aktif olan TEK network logger'ı (.netfox / .pulse / .none) enum ile seçer,
//   • seçilen araç YÜKLÜYSE (#if canImport) geçiş köprüsünü kaydeder,
//   • kararı init sırasında LogFoxUI.install(tools:) ile pakete gönderir.

import Foundation
// @_exported: LogCategory/LogLevel app genelinde görünür → çağrı yerleri `import LogFoxCore` yazmadan
// `.cards` gibi kategorileri ve LogFoxManager loglamasını kullanabilir.
@_exported import LogFoxCore
import LogFoxUI

#if canImport(netfox)
import netfox
#endif
#if canImport(PulseUI)
import PulseUI
#endif
#if canImport(LogFoxNetwork)
import LogFoxNetwork
#endif

// MARK: - App'e özel log kategorileri (genişletin)
//
// LogCategory string-backed'tir; projeye göre kategori ekleyin. Eklenenler her yerden
// `LogFoxManager.shared.info("...", category: .myCategory)` ile kullanılabilir.
public extension LogCategory {
    // ADAPT: projenizin modüllerine göre düzenleyin.
    static let cards: LogCategory = "cards"
    static let accounts: LogCategory = "accounts"
    static let transfers: LogCategory = "transfers"
}

// MARK: - Host konfigürasyonu

/// Projede aktif olan network logger. Bir projede yalnız BİRİ kullanılır.
public enum LogFoxNetworkLogger {
    case netfox
    case pulse
    case none
}

// MARK: - Entegrasyon yöneticisi (NetfoxManager muadili)

public final class LogFoxManager {

    public static let shared = LogFoxManager()
    private init() {}

    /// LogFox'u başlatır ve seçilen network logger'a geçiş köprüsünü kaydeder.
    /// - Parameter networkLogger: Projede aktif olan tek network logger (`.netfox` / `.pulse` / `.none`).
    public func initialize(networkLogger: LogFoxNetworkLogger = .none) {
        #if !PROD
        // ADAPT: feature flag kontrolünüz (NetfoxManager'daki Feature.isDisabled(.netfox) ile aynı patern).
        // guard Feature.isEnabled(.logFox) else { return }

        LogFox.start(.bankingDefault)

        #if canImport(LogFoxNetwork)
        // Network capture — BaseService/URLSession config'e DOKUNMADAN, SSL kırmadan (swizzle + trust kabul).
        LogFoxNetwork.startAutomaticCapture()
        #endif

        Task { @MainActor in
            var bridges: [any ExternalToolBridge] = []

            switch networkLogger {
            case .netfox:
                #if canImport(netfox)
                bridges.append(NetfoxBridge())
                #endif
            case .pulse:
                #if canImport(PulseUI)
                bridges.append(PulseBridge())
                #endif
            case .none:
                break
            }

            LogFoxUI.install(tools: bridges)   // karar pakete init'te gönderilir
        }
        #endif
        // PROD: bilinçli olarak kapalı. Gerekirse remote-flag ile açın.
    }

    // MARK: - Logging (app bu manager üzerinden loglar; LogFox'a doğrudan bağlanmaz)
    //
    // file/line/function OTOMATİK doldurulur — sadece mesaj (+ ops. category/metadata) yaz:
    //   LogFoxManager.shared.info("Login başarılı", category: .auth)
    //   LogFoxManager.shared.error(error, category: .payment)
    // file/line/function parametrelerine DOKUNMA; default'ları (#fileID/#line/#function) çağrı yerini yakalar.
    // (Swift'te call-site bilgisini yakalamanın tek yolu doğrudan default parametredir; tek struct'a
    //  sarmak yakalamayı bozar — manager'ın konumunu loglar.)
    // LogFox başlatılmadıysa (ör. PROD) çağrılar güvenle no-op'tur.

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

// MARK: - Netfox köprüsü (yalnız netfox link'liyse derlenir)

#if canImport(netfox)
struct NetfoxBridge: ExternalToolBridge {
    let title = "Netfox"
    var systemImage: String? { "network" }

    @MainActor func open() {
        LogFoxUI.dismiss()                 // önce LogFox'u kapat
        NFX.sharedInstance().show()        // Netfox kendi penceresinde açılır
    }
}
#endif

// MARK: - Pulse köprüsü (yalnız PulseUI link'liyse derlenir)

#if canImport(PulseUI)
struct PulseBridge: ExternalToolBridge {
    let title = "Pulse"
    var systemImage: String? { "waveform.path.ecg" }

    @MainActor func open() {
        // Pulse gömülebilir bir SwiftUI ekranıdır → LogFox kendi penceresinde sunar.
        LogFoxUI.presentExternal {
            PulseConsoleScreen()
        }
    }
}

private struct PulseConsoleScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ConsoleView()   // varsayılan paylaşılan LoggerStore'u gösterir
                .navigationTitle("Pulse")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Kapat") { dismiss() }   // LogFox viewer'a geri döner
                    }
                }
        }
    }
}
#endif

//  LogFoxIntegration.swift
//
//  DROP-IN TEMPLATE — bu dosya LogFox paketinin parçası DEĞİLDİR (Sources/ dışında, SPM derlemez).
//  Host uygulamaya (örn. Core/Utils/ altına) kopyalayın. `// ADAPT:` ile işaretli yerleri projeye uyarlayın.
//
//  Bu dosya:
//   • LogFox'u NetfoxManager paterniyle başlatır,
//   • Netfox ve/veya Pulse YÜKLÜYSE (#if canImport) ve host onları ETKİNLEŞTİRDİYSE geçiş köprülerini kaydeder,
//   • kararı init sırasında LogFoxUI.install(tools:) ile pakete gönderir.

import Foundation
import LogFoxCore
import LogFoxUI

#if canImport(netfox)
import netfox
#endif
#if canImport(PulseUI)
import PulseUI
#endif

// MARK: - Host konfigürasyonu

/// Host'un hangi dış araçlara geçişe izin verdiği. Init sırasında verilir.
public struct LogFoxToolsConfig {
    public var enableNetfox: Bool
    public var enablePulse: Bool

    public init(enableNetfox: Bool = true, enablePulse: Bool = true) {
        self.enableNetfox = enableNetfox
        self.enablePulse = enablePulse
    }
}

// MARK: - Entegrasyon yöneticisi (NetfoxManager muadili)

public final class LogFoxManager {

    public static let shared = LogFoxManager()
    private init() {}

    /// LogFox'u başlatır ve etkin dış araç köprülerini kaydeder.
    public func initialize(tools: LogFoxToolsConfig = LogFoxToolsConfig()) {
        #if !PROD
        // ADAPT: feature flag kontrolünüz (NetfoxManager'daki Feature.isDisabled(.netfox) ile aynı patern).
        // guard Feature.isEnabled(.logFox) else { return }

        LogFox.start(.bankingDefault)

        Task { @MainActor in
            var bridges: [any ExternalToolBridge] = []

            #if canImport(netfox)
            if tools.enableNetfox {
                bridges.append(NetfoxBridge())
            }
            #endif

            #if canImport(PulseUI)
            if tools.enablePulse {
                bridges.append(PulseBridge())
            }
            #endif

            LogFoxUI.install(tools: bridges)   // karar pakete init'te gönderilir
        }
        #endif
        // PROD: bilinçli olarak kapalı. Gerekirse remote-flag ile açın.
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

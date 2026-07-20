#if canImport(UIKit)
import SwiftUI

/// Yakalanmış bir network kaydını **düzenlenebilir mock'a** çevirir: status/gövde/gecikme
/// değiştirilir ya da taşıma hatası seçilir; kaydedilince eşleşen sonraki istekler ağa
/// çıkmadan bu yanıtı alır (`OlafNetwork.addMock`).
struct MockEditorView: View {

    @Environment(\.dismiss) private var dismiss

    private let sourceMethod: String?
    private let sourceHeaders: [(key: String, value: String)]

    @State private var urlContains: String
    @State private var limitToMethod = true
    @State private var mode: Mode = .response
    @State private var statusText: String
    @State private var delayText = "0"
    @State private var bodyText: String
    @State private var errorChoice: TransportErrorChoice = .notConnected

    private enum Mode: Hashable {
        case response, transportError
    }

    /// Sık kullanılan taşıma hataları (mock `.failure` senaryoları).
    private enum TransportErrorChoice: String, CaseIterable, Identifiable {
        case notConnected, timedOut, connectionLost, cannotFindHost

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notConnected: return "İnternet yok"
            case .timedOut: return "Zaman aşımı"
            case .connectionLost: return "Bağlantı koptu"
            case .cannotFindHost: return "Host bulunamadı"
            }
        }

        var code: URLError.Code {
            switch self {
            case .notConnected: return .notConnectedToInternet
            case .timedOut: return .timedOut
            case .connectionLost: return .networkConnectionLost
            case .cannotFindHost: return .cannotFindHost
            }
        }
    }

    init(info: NetworkLogInfo) {
        sourceMethod = info.method
        sourceHeaders = info.responseHeaders
        _urlContains = State(initialValue: info.suggestedMockPattern)
        _statusText = State(initialValue: String(info.statusCode ?? 200))
        _bodyText = State(initialValue: info.responseBody ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                matchSection
                responseSection
                simulationSection
            }
            .navigationTitle("Mock'a Çevir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Bölümler

    private var matchSection: some View {
        Section {
            TextField("URL parçası", text: $urlContains)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if let method = sourceMethod {
                Toggle("Yalnız \(method.uppercased()) istekleri", isOn: $limitToMethod)
            }
        } header: {
            Text("Eşleşme")
        } footer: {
            Text("URL'i bu parçayı içeren sonraki istekler ağa çıkmadan mock yanıtı alır.")
        }
    }

    private var responseSection: some View {
        Section {
            Picker("Tür", selection: $mode) {
                Text("Yanıt").tag(Mode.response)
                Text("Taşıma hatası").tag(Mode.transportError)
            }
            .pickerStyle(.segmented)

            switch mode {
            case .response:
                LabeledContent("Durum kodu") {
                    TextField("200", text: $statusText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                TextEditor(text: $bodyText)
                    .font(.callout.monospaced())
                    .frame(minHeight: 160)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            case .transportError:
                Picker("Hata", selection: $errorChoice) {
                    ForEach(TransportErrorChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            }
        } header: {
            Text("Yanıt")
        } footer: {
            if mode == .response {
                Text("Gövdeyi dilediğiniz gibi düzenleyin; yakalanan yanıt header'ları mock'a taşınır.")
            } else {
                Text("HTTP yanıtı yerine seçilen taşıma hatası fırlatılır (offline/timeout senaryoları).")
            }
        }
    }

    private var simulationSection: some View {
        Section {
            LabeledContent("Gecikme (sn)") {
                TextField("0", text: $delayText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
            }
        } footer: {
            Text("Yanıt bu kadar saniye geciktirilir (yavaş ağ simülasyonu); bu sürede istek \"Aktif istekler\" barında görünür.")
        }
    }

    // MARK: - Kaydet

    private var canSave: Bool {
        let pattern = urlContains.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }
        if mode == .response, Int(statusText) == nil { return false }
        return true
    }

    private func save() {
        let pattern = urlContains.trimmingCharacters(in: .whitespacesAndNewlines)
        let method = limitToMethod ? sourceMethod : nil
        let delay = TimeInterval(delayText.replacingOccurrences(of: ",", with: ".")) ?? 0

        let mock: OlafMockResponse
        switch mode {
        case .transportError:
            mock = .failure(
                urlContains: pattern, method: method,
                error: errorChoice.code, delaySeconds: delay
            )
        case .response:
            var headers = Dictionary(sourceHeaders, uniquingKeysWith: { first, _ in first })
            if headers.isEmpty, Formatting.looksLikeJSON(bodyText) {
                headers["Content-Type"] = "application/json"
            }
            mock = OlafMockResponse(
                urlContains: pattern,
                method: method,
                statusCode: Int(statusText) ?? 200,
                headers: headers,
                body: Data(bodyText.utf8),
                delaySeconds: delay
            )
        }

        OlafNetwork.addMock(mock)
        dismiss()
    }
}
#endif

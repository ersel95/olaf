#if canImport(UIKit)
import SwiftUI

/// Converts a captured network entry into an **editable mock**: status/body/delay can be
/// changed, or a transport error can be chosen; once saved, matching subsequent requests get
/// this response without hitting the network (`OlafNetwork.addMock`).
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

    /// Commonly used transport errors (mock `.failure` scenarios).
    private enum TransportErrorChoice: String, CaseIterable, Identifiable {
        case notConnected, timedOut, connectionLost, cannotFindHost

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notConnected: return "No internet"
            case .timedOut: return "Timed out"
            case .connectionLost: return "Connection lost"
            case .cannotFindHost: return "Host not found"
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
            .navigationTitle("Convert to Mock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var matchSection: some View {
        Section {
            TextField("URL fragment", text: $urlContains)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if let method = sourceMethod {
                Toggle("Only \(method.uppercased()) requests", isOn: $limitToMethod)
            }
        } header: {
            Text("Match")
        } footer: {
            Text("Subsequent requests whose URL contains this fragment get the mock response without hitting the network.")
        }
    }

    private var responseSection: some View {
        Section {
            Picker("Type", selection: $mode) {
                Text("Response").tag(Mode.response)
                Text("Transport error").tag(Mode.transportError)
            }
            .pickerStyle(.segmented)

            switch mode {
            case .response:
                LabeledContent("Status code") {
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
                Picker("Error", selection: $errorChoice) {
                    ForEach(TransportErrorChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            }
        } header: {
            Text("Response")
        } footer: {
            if mode == .response {
                Text("Edit the body as you like; the captured response headers are carried over to the mock.")
            } else {
                Text("The selected transport error is thrown instead of an HTTP response (offline/timeout scenarios).")
            }
        }
    }

    private var simulationSection: some View {
        Section {
            LabeledContent("Delay (sec)") {
                TextField("0", text: $delayText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
            }
        } footer: {
            Text("The response is delayed by this many seconds (slow network simulation); during this time the request appears in the \"Active requests\" bar.")
        }
    }

    // MARK: - Save

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

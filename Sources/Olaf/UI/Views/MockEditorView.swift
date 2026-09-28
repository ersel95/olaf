#if canImport(UIKit)
import SwiftUI

/// Builds or edits a **mock variant**: status/body/delay can be changed or a transport error
/// chosen, a template can be applied, and the edited response can be saved back to the library.
///
/// Opened two ways — from a captured entry ("Convert to Mock", creating a new variant on a new or
/// existing endpoint), or from an endpoint's variant list to edit one that's already saved. In the
/// second case **"Reset to captured response"** restores the response the variant was created with.
struct MockEditorView: View {

    @Environment(\.dismiss) private var dismiss

    private let target: Target
    private let sourceMethod: String?

    @State private var urlContains: String
    @State private var limitToMethod = true
    @State private var variantName: String
    @State private var mode: Mode
    @State private var statusText: String
    @State private var delayText: String
    @State private var bodyText: String
    @State private var errorChoice: TransportErrorChoice
    @State private var headers: [String: String]
    @State private var capturedPayload: OlafMockPayload
    @State private var templates: [OlafMockTemplate] = []
    @State private var isNamingTemplate = false
    @State private var templateName = ""

    private enum Target {
        /// A new variant, built from a captured entry. The endpoint is created or extended on save.
        case newVariant
        /// An existing variant of an existing endpoint.
        case existingVariant(endpointID: UUID, variantID: UUID)
    }

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

        static func matching(_ code: URLError.Code) -> TransportErrorChoice {
            allCases.first { $0.code == code } ?? .notConnected
        }
    }

    /// "Convert to Mock" from a captured network entry.
    init(info: NetworkLogInfo) {
        target = .newVariant
        sourceMethod = info.method

        let payload = OlafMockPayload(
            statusCode: info.statusCode ?? 200,
            headers: Dictionary(info.responseHeaders, uniquingKeysWith: { first, _ in first }),
            body: Data((info.responseBody ?? "").utf8)
        )
        _urlContains = State(initialValue: info.suggestedMockPattern)
        _variantName = State(initialValue: Self.defaultVariantName(statusCode: info.statusCode))
        _mode = State(initialValue: .response)
        _statusText = State(initialValue: String(info.statusCode ?? 200))
        _delayText = State(initialValue: "0")
        _bodyText = State(initialValue: info.responseBody ?? "")
        _errorChoice = State(initialValue: .notConnected)
        _headers = State(initialValue: payload.headers)
        _capturedPayload = State(initialValue: payload)
    }

    /// Editing a variant that is already saved on an endpoint.
    init(endpoint: OlafMockEndpoint, variant: OlafMockVariant) {
        target = .existingVariant(endpointID: endpoint.id, variantID: variant.id)
        sourceMethod = endpoint.method

        _urlContains = State(initialValue: endpoint.urlContains)
        _limitToMethod = State(initialValue: endpoint.method != nil)
        _variantName = State(initialValue: variant.name)
        _mode = State(initialValue: variant.payload.transportError == nil ? .response : .transportError)
        _statusText = State(initialValue: String(variant.payload.statusCode))
        _delayText = State(initialValue: Self.delayString(variant.payload.delaySeconds))
        _bodyText = State(initialValue: String(decoding: variant.payload.body, as: UTF8.self))
        _errorChoice = State(
            initialValue: variant.payload.transportError.map(TransportErrorChoice.matching) ?? .notConnected
        )
        _headers = State(initialValue: variant.payload.headers)
        _capturedPayload = State(initialValue: variant.capturedPayload)
    }

    var body: some View {
        CompatNavigationStack {
            Form {
                nameSection
                matchSection
                responseSection
                simulationSection
                librarySection
            }
            .navigationTitle(isEditingExisting ? "Edit Variant" : "Convert to Mock")
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
            .onAppear { templates = OlafNetwork.mockTemplates }
            .alert("Save as template", isPresented: $isNamingTemplate) {
                TextField("Name", text: $templateName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveAsTemplate() }
                    .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("The response is saved without a URL, so it can be reused on any endpoint or as the global override.")
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Variant name", text: $variantName)
        } header: {
            Text("Variant")
        } footer: {
            Text("The name this response is listed under on the endpoint — \"Success\", \"Empty\", \"500\". You can save several and switch between them.")
        }
    }

    @ViewBuilder
    private var matchSection: some View {
        if isEditingExisting {
            Section {
                LabeledRow("URL fragment") {
                    Text(urlContains)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledRow("Method", value: sourceMethod ?? "All")
            } header: {
                Text("Match")
            } footer: {
                Text("The match rule belongs to the endpoint and is shared by all of its variants.")
            }
        } else {
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
                Text(matchFooter)
            }
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
                LabeledRow("Status code") {
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
            LabeledRow("Delay (sec)") {
                TextField("0", text: $delayText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
            }
        } footer: {
            Text("The response is delayed by this many seconds (slow network simulation); during this time the request appears in the \"Active requests\" bar.")
        }
    }

    private var librarySection: some View {
        Section {
            Menu {
                ForEach(templates) { template in
                    Button(template.name) { apply(template) }
                }
            } label: {
                Label("Apply template", systemImage: "square.on.square")
            }

            Button {
                templateName = variantName
                isNamingTemplate = true
            } label: {
                Label("Save as template", systemImage: "tray.and.arrow.down")
            }

            Button {
                fill(from: capturedPayload)
            } label: {
                Label("Reset to captured response", systemImage: "arrow.uturn.backward")
            }
            .disabled(!isModified)
        } header: {
            Text("Library")
        } footer: {
            Text(isModified
                 ? "Reset restores the response this variant was created from, discarding the edits above."
                 : "This response matches the one it was created from — nothing to reset.")
        }
    }

    // MARK: - Derived state

    private var isEditingExisting: Bool {
        if case .existingVariant = target { return true }
        return false
    }

    private var matchFooter: String {
        let pattern = trimmedPattern
        guard !pattern.isEmpty,
              OlafNetwork.mockEndpoints.contains(where: {
                  $0.urlContains == pattern.lowercased() && $0.method == effectiveMethod?.uppercased()
              }) else {
            return "Subsequent requests whose URL contains this fragment get the mock response without hitting the network."
        }
        return "An endpoint with this rule already exists — the variant is added to it and switched on."
    }

    private var isModified: Bool { currentPayload != capturedPayload }

    private var trimmedPattern: String {
        urlContains.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveMethod: String? {
        limitToMethod ? sourceMethod : nil
    }

    private var currentPayload: OlafMockPayload {
        let delay = TimeInterval(delayText.replacingOccurrences(of: ",", with: ".")) ?? 0
        switch mode {
        case .transportError:
            return .failure(error: errorChoice.code, delaySeconds: delay)
        case .response:
            var resolvedHeaders = headers
            if resolvedHeaders.isEmpty, Formatting.looksLikeJSON(bodyText) {
                resolvedHeaders["Content-Type"] = "application/json"
            }
            return OlafMockPayload(
                statusCode: Int(statusText) ?? 200,
                headers: resolvedHeaders,
                body: Data(bodyText.utf8),
                delaySeconds: delay
            )
        }
    }

    private var canSave: Bool {
        guard !variantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if isEditingExisting { return mode == .transportError || Int(statusText) != nil }
        guard !trimmedPattern.isEmpty else { return false }
        if mode == .response, Int(statusText) == nil { return false }
        return true
    }

    // MARK: - Actions

    private func fill(from payload: OlafMockPayload) {
        mode = payload.transportError == nil ? .response : .transportError
        statusText = String(payload.statusCode)
        bodyText = String(decoding: payload.body, as: UTF8.self)
        delayText = Self.delayString(payload.delaySeconds)
        headers = payload.headers
        if let transportError = payload.transportError {
            errorChoice = .matching(transportError)
        }
    }

    private func apply(_ template: OlafMockTemplate) {
        fill(from: template.payload)
        if variantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            variantName = template.name
        }
    }

    private func saveAsTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        OlafNetwork.addTemplate(OlafMockTemplate(name: name, payload: currentPayload))
        templates = OlafNetwork.mockTemplates
    }

    private func save() {
        let name = variantName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch target {
        case .existingVariant(let endpointID, let variantID):
            let payload = currentPayload
            OlafNetwork.updateVariant(id: variantID, in: endpointID) { variant in
                variant.name = name
                variant.payload = payload
            }

        case .newVariant:
            let variant = OlafMockVariant(name: name, payload: currentPayload)
            // Saving a second response for a rule that already exists extends that endpoint —
            // a duplicate entry would sit behind the first one and never be served.
            if let existing = OlafNetwork.mockEndpoints.first(where: {
                $0.urlContains == trimmedPattern.lowercased() && $0.method == effectiveMethod?.uppercased()
            }) {
                OlafNetwork.addVariant(variant, to: existing.id)
            } else {
                OlafNetwork.addEndpoint(OlafMockEndpoint(
                    urlContains: trimmedPattern,
                    method: effectiveMethod,
                    variants: [variant],
                    activeVariantID: variant.id
                ))
            }
        }
        dismiss()
    }

    // MARK: - Helpers

    private static func delayString(_ seconds: TimeInterval) -> String {
        seconds == 0 ? "0" : String(format: "%g", seconds)
    }

    /// A first guess at the variant name, so the common case needs no typing.
    private static func defaultVariantName(statusCode: Int?) -> String {
        guard let statusCode else { return "Captured" }
        return "\(statusCode) response"
    }
}
#endif

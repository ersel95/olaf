#if canImport(UIKit)
import SwiftUI
import UIKit

/// Detail for a single entry: colored status header + grouped List + navigation to sub-screens
/// (headers, body, cURL, metrics). Non-`.network` entries show level + message + metadata.
struct LogDetailView: View {
    let entry: LogEntry

    @State private var didCopy = false
    @State private var isMockEditorPresented = false

    private var network: NetworkLogInfo? { NetworkLogInfo(entry: entry) }

    var body: some View {
        List {
            if let network {
                networkSections(network)
            } else {
                logSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(network != nil ? "Network" : "Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { shareMenu }
        }
        .sheet(isPresented: $isMockEditorPresented) {
            if let network {
                MockEditorView(info: network)
            }
        }
        .copyToast($didCopy)
    }

    /// Share menu: Simple/Full/cURL for network, full text for log; also copy.
    @ViewBuilder
    private var shareMenu: some View {
        Menu {
            if let info = network {
                Button {
                    share(ShareFormatter.simpleNetworkLog(entry: entry, info: info))
                } label: { Label("Simple log", systemImage: "doc.text") }
                Button {
                    share(ShareFormatter.fullNetworkLog(entry: entry, info: info))
                } label: { Label("Full log (with bodies)", systemImage: "doc.richtext") }
                Button {
                    share(CurlBuilder.curl(from: info))
                } label: { Label("cURL", systemImage: "terminal") }
            } else {
                Button {
                    share(ShareFormatter.logDetail(entry: entry))
                } label: { Label("Share log", systemImage: "doc.text") }
            }
            Divider()
            Button {
                let text = network.map { ShareFormatter.fullNetworkLog(entry: entry, info: $0) }
                    ?? ShareFormatter.logDetail(entry: entry)
                olafCopy(text, showing: $didCopy)
            } label: { Label("Copy to clipboard", systemImage: "doc.on.doc") }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share")
    }

    private func share(_ text: String) {
        presentShareSheet([text])
    }

    // MARK: - Network

    @ViewBuilder
    private func networkSections(_ info: NetworkLogInfo) -> some View {
        Section {
            StatusBanner(info: info) {
                olafCopy(info.url ?? info.path, showing: $didCopy)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section("Summary") {
            if let method = info.method { kv("Method", method, mono: true) }
            kv("URL", info.url ?? "-", mono: true)
            if let status = info.statusCode { kv("Status", String(status)) }
            if info.cancelled { kv("Status", "Cancelled") }
            if info.mocked { kv("Source", "Mock (no network call)") }
            if let ms = info.durationMs { kv("Duration", "\(ms) ms") }
            if let b = info.requestBytes { kv("Request size", Formatting.byteCount(b)) }
            if let b = info.responseBytes { kv("Response size", Formatting.byteCount(b)) }
        }

        if let error = info.error {
            Section("Error") {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button {
                    olafCopy(error, showing: $didCopy)
                } label: {
                    Label("Copy error", systemImage: "doc.on.doc")
                }
            }
        }

        Section("Request") {
            NavigationLink {
                HeadersListView(title: "Request Headers", headers: info.requestHeaders)
            } label: {
                rowLabel("Headers", count: info.requestHeaders.count, systemImage: "arrow.up.circle")
            }
            .disabled(info.requestHeaders.isEmpty)

            if let body = info.requestBody, !body.isEmpty {
                NavigationLink {
                    TextViewerView(title: "Request Body", rawText: body)
                } label: {
                    rowLabel("View body", systemImage: "doc.plaintext")
                }
            }
        }

        Section("Response") {
            NavigationLink {
                HeadersListView(title: "Response Headers", headers: info.responseHeaders)
            } label: {
                rowLabel("Headers", count: info.responseHeaders.count, systemImage: "arrow.down.circle")
            }
            .disabled(info.responseHeaders.isEmpty)

            if let body = info.responseBody, !body.isEmpty {
                NavigationLink {
                    TextViewerView(title: "Response Body", rawText: body)
                } label: {
                    rowLabel("View body", systemImage: "doc.plaintext")
                }
            }

            // image/* responses (if under the size limit) are previewed directly.
            if let imageData = info.responseImageData, let image = UIImage(data: imageData) {
                HStack {
                    Spacer()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }

        Section {
            NavigationLink {
                TextViewerView(title: "cURL", rawText: CurlBuilder.curl(from: info))
            } label: {
                rowLabel("cURL", systemImage: "terminal")
            }
            Button {
                isMockEditorPresented = true
            } label: {
                rowLabel("Convert to Mock", systemImage: "arrow.triangle.2.circlepath")
            }
        } footer: {
            Text("Convert to Mock: edit and save this response; matching subsequent requests get your response without hitting the network.")
        }

        if info.hasTimings {
            Section("Timing") {
                if let v = info.dnsMs { kv("DNS", "\(v) ms") }
                if let v = info.connectMs { kv("Connect (TCP)", "\(v) ms") }
                if let v = info.tlsMs { kv("TLS", "\(v) ms") }
                if let v = info.ttfbMs { kv("First byte (TTFB)", "\(v) ms") }
                if let p = info.protocolName { kv("Protocol", p, mono: true) }
                if let reused = info.reusedConnection {
                    kv("Connection reused", reused ? "Yes" : "No")
                }
            }
        }

        Section("Metrics") {
            kv("Thread", entry.thread)
            kv("Time", entry.date.formatted(date: .numeric, time: .standard))
        }
    }

    // MARK: - Log

    @ViewBuilder
    private var logSections: some View {
        Section {
            LevelBanner(level: entry.level, category: entry.category)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }

        Section("Message") {
            Text(entry.message).font(.callout.monospaced()).textSelection(.enabled)
        }

        if let decodingDetail = entry.metadata["decoding.detail"] {
            Section("Decoding Error") {
                if let path = entry.metadata["decoding.path"] { kv("Field", path, mono: true) }
                if let type = entry.metadata["decoding.type"] { kv("Type", type, mono: true) }
                if let url = entry.metadata["url"] { kv("URL", url, mono: true) }
                Text(decodingDetail)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                if let body = entry.metadata["responseBody"], !body.isEmpty {
                    NavigationLink {
                        TextViewerView(title: "Response Body", rawText: body)
                    } label: {
                        rowLabel("View body", systemImage: "doc.plaintext")
                    }
                }
            }
        }

        if !genericMetadata.isEmpty {
            Section("Metadata") {
                ForEach(genericMetadata, id: \.key) { key, value in
                    kv(key, value, mono: true)
                }
            }
        }

        Section("Source") {
            kv("File", "\(entry.fileName):\(entry.line)", mono: true)
            kv("Function", entry.function, mono: true)
            kv("Thread", entry.thread)
            kv("Time", entry.date.formatted(date: .numeric, time: .standard))
        }
    }

    // MARK: - Helpers

    /// Keys already shown in the "Decoding Error" section are not repeated in the Metadata list.
    private var genericMetadata: [(key: String, value: String)] {
        let hasDecodingSection = entry.metadata["decoding.detail"] != nil
        return entry.metadata
            .filter { key, _ in
                guard hasDecodingSection else { return true }
                return !key.hasPrefix("decoding.") && key != "responseBody" && key != "url"
            }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }

    @ViewBuilder
    private func kv(_ key: String, _ value: String, mono: Bool = false) -> some View {
        LabeledContent {
            Text(value)
                .font(mono ? .callout.monospaced() : .callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(key).font(.callout)
        }
    }

    @ViewBuilder
    private func rowLabel(_ title: String, count: Int? = nil, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if let count {
                Spacer()
                Text("\(count)").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Banners

/// Network status header (full-width colored banner).
private struct StatusBanner: View {
    let info: NetworkLogInfo
    /// Copies the full URL to the clipboard when the copy button on the right is tapped.
    var onCopyURL: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            StatusPill(statusCode: info.statusCode, isFailure: info.isFailure)
            MethodBadge(method: info.method ?? "GET")
            Text(info.path)
                .font(.subheadline.monospaced())
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button(action: onCopyURL) {
                Image(systemName: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy URL")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(info.isFailure ? Color.red.opacity(0.85) : Color.accentColor.opacity(0.9))
    }
}

/// Log level header.
private struct LevelBanner: View {
    let level: LogLevel
    let category: LogCategory

    var body: some View {
        HStack(spacing: 10) {
            Text(level.symbol)
            Text(level.name).font(.headline).foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(category.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(level.color.opacity(0.85))
    }
}
#endif

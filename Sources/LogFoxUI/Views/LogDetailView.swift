#if canImport(UIKit)
import SwiftUI
import LogFoxCore

/// Tek kaydın tam detayı — Pulse tarzı gruplu (inset) kart düzeni.
/// `.network` kayıtları status/URL/header/gövde bölümleriyle; diğerleri seviye + mesaj + metadata.
struct LogDetailView: View {
    let entry: LogEntry

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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = entry.oneLineDescription
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Kopyala")
            }
        }
    }

    // MARK: - Network bölümleri

    @ViewBuilder
    private func networkSections(_ info: NetworkLogInfo) -> some View {
        Section {
            HStack(spacing: 10) {
                StatusPill(statusCode: info.statusCode, isFailure: info.isFailure)
                MethodBadge(method: info.method ?? "GET")
                Spacer()
                if let ms = info.durationMs {
                    Text("\(ms)ms").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }

        Section("URL") {
            Text(info.url ?? "-")
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }

        if let error = info.error {
            Section("Hata") {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
        }

        Section("Bilgi") {
            if let ms = info.durationMs { kv("Süre", "\(ms) ms") }
            if let b = info.requestBytes { kv("İstek boyutu", Formatting.byteCount(b)) }
            if let b = info.responseBytes { kv("Yanıt boyutu", Formatting.byteCount(b)) }
            kv("Thread", entry.thread)
            kv("Zaman", entry.date.formatted(date: .numeric, time: .standard))
        }

        if !info.requestHeaders.isEmpty {
            Section("İstek Header'ları") { headerRows(info.requestHeaders) }
        }
        if let body = info.requestBody, !body.isEmpty {
            Section("İstek Gövdesi") { CodeBlock(text: body) }
        }
        if !info.responseHeaders.isEmpty {
            Section("Yanıt Header'ları") { headerRows(info.responseHeaders) }
        }
        if let body = info.responseBody, !body.isEmpty {
            Section("Yanıt Gövdesi") { CodeBlock(text: body) }
        }
    }

    // MARK: - Log bölümleri

    @ViewBuilder
    private var logSections: some View {
        Section {
            HStack(spacing: 8) {
                LevelDot(level: entry.level)
                Text(entry.level.name).font(.callout.weight(.semibold)).foregroundStyle(entry.level.color)
                Spacer()
                Text(entry.category.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }

        Section("Mesaj") {
            Text(entry.message)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }

        if !entry.metadata.isEmpty {
            Section("Metadata") {
                ForEach(entry.metadata.sorted { $0.key < $1.key }, id: \.key) { key, value in
                    kv(key, value, mono: true)
                }
            }
        }

        Section("Kaynak") {
            kv("Dosya", "\(entry.fileName):\(entry.line)", mono: true)
            kv("Fonksiyon", entry.function, mono: true)
            kv("Thread", entry.thread)
            kv("Zaman", entry.date.formatted(date: .numeric, time: .standard))
        }
    }

    // MARK: - Yardımcılar

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
    private func headerRows(_ headers: [(key: String, value: String)]) -> some View {
        ForEach(headers, id: \.key) { header in
            kv(header.key, header.value, mono: true)
        }
    }
}

/// Gövde/JSON için monospace kod bloğu; JSON ise pretty-print + kopyalama.
private struct CodeBlock: View {
    let text: String

    var body: some View {
        let display = Formatting.isJSON(text) ? Formatting.prettyJSON(text) : text
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(display)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            Button {
                UIPasteboard.general.string = display
            } label: {
                Label("Kopyala", systemImage: "doc.on.doc").font(.caption2)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif

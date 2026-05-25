#if canImport(UIKit)
import SwiftUI
import LogFoxCore

/// Tek kaydın detayı: renkli status başlığı + gruplu List + alt ekranlara
/// navigation (header'lar, gövde, cURL, metrikler). `.network` dışı kayıtlar seviye + mesaj + metadata.
struct LogDetailView: View {
    let entry: LogEntry

    @State private var didCopy = false

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
        .copyToast($didCopy)
    }

    /// Netfox tarzı paylaşım menüsü: network için Basit/Tam/cURL, log için tam metin; ayrıca kopyala.
    @ViewBuilder
    private var shareMenu: some View {
        Menu {
            if let info = network {
                Button {
                    share(ShareFormatter.simpleNetworkLog(entry: entry, info: info))
                } label: { Label("Basit log", systemImage: "doc.text") }
                Button {
                    share(ShareFormatter.fullNetworkLog(entry: entry, info: info))
                } label: { Label("Tam log (gövdelerle)", systemImage: "doc.richtext") }
                Button {
                    share(CurlBuilder.curl(from: info))
                } label: { Label("cURL", systemImage: "terminal") }
            } else {
                Button {
                    share(ShareFormatter.logDetail(entry: entry))
                } label: { Label("Logu paylaş", systemImage: "doc.text") }
            }
            Divider()
            Button {
                let text = network.map { ShareFormatter.fullNetworkLog(entry: entry, info: $0) }
                    ?? ShareFormatter.logDetail(entry: entry)
                logFoxCopy(text, showing: $didCopy)
            } label: { Label("Panoya kopyala", systemImage: "doc.on.doc") }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Paylaş")
    }

    private func share(_ text: String) {
        presentShareSheet([text])
    }

    // MARK: - Network

    @ViewBuilder
    private func networkSections(_ info: NetworkLogInfo) -> some View {
        Section {
            StatusBanner(info: info)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }

        Section("Özet") {
            if let method = info.method { kv("Metot", method, mono: true) }
            kv("URL", info.url ?? "-", mono: true)
            if let status = info.statusCode { kv("Durum", String(status)) }
            if let ms = info.durationMs { kv("Süre", "\(ms) ms") }
            if let b = info.requestBytes { kv("İstek boyutu", Formatting.byteCount(b)) }
            if let b = info.responseBytes { kv("Yanıt boyutu", Formatting.byteCount(b)) }
        }

        if let error = info.error {
            Section("Hata") {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button {
                    logFoxCopy(error, showing: $didCopy)
                } label: {
                    Label("Hatayı kopyala", systemImage: "doc.on.doc")
                }
            }
        }

        Section("İstek") {
            NavigationLink {
                HeadersListView(title: "İstek Header'ları", headers: info.requestHeaders)
            } label: {
                rowLabel("Header'lar", count: info.requestHeaders.count, systemImage: "arrow.up.circle")
            }
            .disabled(info.requestHeaders.isEmpty)

            if let body = info.requestBody, !body.isEmpty {
                NavigationLink {
                    TextViewerView(title: "İstek Gövdesi", rawText: body)
                } label: {
                    rowLabel("Gövdeyi görüntüle", systemImage: "doc.plaintext")
                }
            }
        }

        Section("Yanıt") {
            NavigationLink {
                HeadersListView(title: "Yanıt Header'ları", headers: info.responseHeaders)
            } label: {
                rowLabel("Header'lar", count: info.responseHeaders.count, systemImage: "arrow.down.circle")
            }
            .disabled(info.responseHeaders.isEmpty)

            if let body = info.responseBody, !body.isEmpty {
                NavigationLink {
                    TextViewerView(title: "Yanıt Gövdesi", rawText: body)
                } label: {
                    rowLabel("Gövdeyi görüntüle", systemImage: "doc.plaintext")
                }
            }
        }

        Section {
            NavigationLink {
                TextViewerView(title: "cURL", rawText: CurlBuilder.curl(from: info))
            } label: {
                rowLabel("cURL", systemImage: "terminal")
            }
        }

        Section("Metrikler") {
            kv("Thread", entry.thread)
            kv("Zaman", entry.date.formatted(date: .numeric, time: .standard))
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

        Section("Mesaj") {
            Text(entry.message).font(.callout.monospaced()).textSelection(.enabled)
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

// MARK: - Banner'lar

/// Network status başlığı (tam-genişlik renkli banner).
private struct StatusBanner: View {
    let info: NetworkLogInfo

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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(info.isFailure ? Color.red.opacity(0.85) : Color.accentColor.opacity(0.9))
    }
}

/// Log seviyesi başlığı.
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

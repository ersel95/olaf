#if canImport(UIKit)
import SwiftUI

/// Devam eden (henüz tamamlanmamış) network isteklerini gösteren ince bar. Asılı kalan istekler
/// burada geçen süresiyle birlikte görünür; tamamlanınca satır düşer ve kayıt normal listeye girer.
/// 1 sn'lik `TimelineView` tick'i hem süreyi günceller hem listeyi tazeler (yayın mekanizması yok).
struct PendingRequestsBar: View {

    /// Bar en fazla bu kadar satır gösterir; fazlası "+N daha" olarak özetlenir.
    private let maxVisible = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let pending = OlafNetwork.pendingRequests
            if !pending.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pending.prefix(maxVisible)) { request in
                        row(request)
                    }
                    if pending.count > maxVisible {
                        Text("+\(pending.count - maxVisible) istek daha")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
            }
        }
    }

    private func row(_ request: PendingNetworkRequest) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            MethodBadge(method: request.method)
            Text(Self.compactPath(request.url))
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text("\(request.elapsedSeconds) sn")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(request.elapsedSeconds >= 10 ? .orange : .secondary)
        }
    }

    /// Satırda kısa gösterim: host + path (query'siz).
    private static func compactPath(_ url: String) -> String {
        guard let components = URLComponents(string: url) else { return url }
        let host = components.host ?? ""
        let path = components.path.isEmpty ? "/" : components.path
        return host + path
    }
}
#endif

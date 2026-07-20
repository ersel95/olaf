#if canImport(UIKit)
import SwiftUI

/// Thin bar showing in-flight (not yet completed) network requests. Requests that are hanging
/// appear here along with their elapsed time; once complete the row drops and the entry enters
/// the normal list. A 1-second `TimelineView` tick both updates the elapsed time and refreshes
/// the list (there is no publish mechanism).
struct PendingRequestsBar: View {

    /// The bar shows at most this many rows; the rest is summarized as "+N more".
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
                        Text("+\(pending.count - maxVisible) more requests")
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
            Text("\(request.elapsedSeconds)s")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(request.elapsedSeconds >= 10 ? .orange : .secondary)
        }
    }

    /// Compact row display: host + path (no query).
    private static func compactPath(_ url: String) -> String {
        guard let components = URLComponents(string: url) else { return url }
        let host = components.host ?? ""
        let path = components.path.isEmpty ? "/" : components.path
        return host + path
    }
}
#endif

#if canImport(UIKit)
import SwiftUI

/// A single log row. `.network` entries render as a compact network row; others
/// render as a level-colored log row.
struct LogRowView: View {
    let entry: LogEntry
    /// Decode errors folded under this network entry (badge only; details live
    /// in the network detail screen). Always 0 for non-network entries.
    var decodeErrorCount: Int = 0

    var body: some View {
        if let network = NetworkLogInfo(entry: entry) {
            NetworkRow(info: network, date: entry.date, decodeErrorCount: decodeErrorCount)
        } else {
            LogMessageRow(entry: entry)
        }
    }
}

// MARK: - Network row

private struct NetworkRow: View {
    let info: NetworkLogInfo
    let date: Date
    var decodeErrorCount: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Status + method share the left column so the whole width is left for the path.
            VStack(spacing: 3) {
                StatusPill(statusCode: info.statusCode, isFailure: info.isFailure)
                MethodBadge(method: info.method ?? "GET")
            }
            .frame(minWidth: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Query-free path, truncated from the head: the endpoint's tail — the part
                    // that says where the request went — always stays visible.
                    Text(info.pathWithoutQuery)
                        .font(.subheadline.monospaced())
                        .lineLimit(2)
                        .truncationMode(.head)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if decodeErrorCount > 0 {
                        DecodeBadge(count: decodeErrorCount)
                    }
                }
                HStack(spacing: 8) {
                    if !info.host.isEmpty {
                        Text(info.host).lineLimit(1)
                    }
                    Text(PlainTextFormatter.timeFormatter.string(from: date))
                    if let ms = info.durationMs { Text("· \(ms)ms") }
                    if let bytes = info.responseBytes, bytes > 0 { Text("· \(Formatting.byteCount(bytes))") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Log message row

private struct LogMessageRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LevelDot(level: entry.level)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    Text(entry.category.rawValue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    Text(entry.level.name)
                        .foregroundStyle(entry.level.color)
                    Text(PlainTextFormatter.timeFormatter.string(from: entry.date))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
#endif

#if canImport(UIKit)
import SwiftUI
import LogFoxCore

/// Tek log satırı. `.network` kayıtları kompakt network satırı olarak, diğerleri
/// seviye-renkli log satırı olarak render edilir.
struct LogRowView: View {
    let entry: LogEntry

    var body: some View {
        if let network = NetworkLogInfo(entry: entry) {
            NetworkRow(info: network, date: entry.date)
        } else {
            LogMessageRow(entry: entry)
        }
    }
}

// MARK: - Network satırı

private struct NetworkRow: View {
    let info: NetworkLogInfo
    let date: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusPill(statusCode: info.statusCode, isFailure: info.isFailure)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    MethodBadge(method: info.method ?? "GET")
                    Text(info.path)
                        .font(.subheadline.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
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

// MARK: - Log mesajı satırı

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

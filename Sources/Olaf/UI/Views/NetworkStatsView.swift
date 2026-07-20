#if canImport(UIKit)
import SwiftUI

/// Summary statistics for the visible (filtered) network entries: error rate, duration
/// distribution, method/status breakdown, slowest requests, and hosts.
struct NetworkStatsView: View {

    let entries: [LogEntry]
    @Environment(\.dismiss) private var dismiss

    private var stats: NetworkStats { NetworkStats.compute(from: entries) }

    var body: some View {
        NavigationStack {
            Group {
                if stats.totalRequests == 0 {
                    ContentUnavailableView(
                        "No network entries",
                        systemImage: "chart.bar",
                        description: Text("No network requests were found in the visible list to compute statistics from.")
                    )
                } else {
                    statsList
                }
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statsList: some View {
        let stats = self.stats
        return List {
            Section("Summary") {
                LabeledContent("Total requests", value: "\(stats.totalRequests)")
                LabeledContent("Errors", value: "\(stats.failureCount) (%\(stats.failurePercent))")
                if stats.cancelledCount > 0 {
                    LabeledContent("Cancelled", value: "\(stats.cancelledCount)")
                }
                if let ms = stats.averageDurationMs { LabeledContent("Average duration", value: "\(ms) ms") }
                if let ms = stats.medianDurationMs { LabeledContent("Median duration", value: "\(ms) ms") }
                if let ms = stats.p95DurationMs { LabeledContent("p95 duration", value: "\(ms) ms") }
                LabeledContent("Request size", value: Formatting.byteCount(stats.totalRequestBytes))
                LabeledContent("Response size", value: Formatting.byteCount(stats.totalResponseBytes))
            }

            if !stats.statusClassCounts.isEmpty {
                Section("Status distribution") {
                    ForEach(stats.statusClassCounts, id: \.name) { item in
                        barRow(name: item.name, count: item.count,
                               maxCount: stats.totalRequests, color: statusColor(item.name))
                    }
                }
            }

            if !stats.methodCounts.isEmpty {
                Section("Methods") {
                    ForEach(stats.methodCounts, id: \.name) { item in
                        barRow(name: item.name, count: item.count,
                               maxCount: stats.methodCounts.first?.count ?? 1, color: .accentColor)
                    }
                }
            }

            if !stats.slowest.isEmpty {
                Section("Slowest requests") {
                    ForEach(Array(stats.slowest.enumerated()), id: \.offset) { _, item in
                        LabeledContent {
                            Text("\(item.durationMs) ms").monospacedDigit()
                        } label: {
                            Text(item.path)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            if !stats.hostCounts.isEmpty {
                Section("Hosts") {
                    ForEach(stats.hostCounts, id: \.name) { item in
                        barRow(name: item.name, count: item.count,
                               maxCount: stats.hostCounts.first?.count ?? 1, color: .teal)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func barRow(name: String, count: Int, maxCount: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.callout.monospaced())
                Spacer()
                Text("\(count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(color.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: geometry.size.width * CGFloat(count) / CGFloat(max(1, maxCount)))
                    }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }

    private func statusColor(_ name: String) -> Color {
        switch name {
        case "2xx": return .green
        case "3xx": return .teal
        case "4xx": return .orange
        case "5xx", "Error": return .red
        default: return .gray
        }
    }
}
#endif

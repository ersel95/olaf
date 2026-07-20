#if canImport(UIKit)
import SwiftUI

/// Görünen (filtreli) network kayıtlarının özet istatistikleri: hata oranı, süre dağılımı,
/// metot/durum kırılımı, en yavaş istekler ve host'lar.
struct NetworkStatsView: View {

    let entries: [LogEntry]
    @Environment(\.dismiss) private var dismiss

    private var stats: NetworkStats { NetworkStats.compute(from: entries) }

    var body: some View {
        NavigationStack {
            Group {
                if stats.totalRequests == 0 {
                    ContentUnavailableView(
                        "Network kaydı yok",
                        systemImage: "chart.bar",
                        description: Text("Görünen listede istatistik çıkarılacak network isteği bulunamadı.")
                    )
                } else {
                    statsList
                }
            }
            .navigationTitle("İstatistikler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private var statsList: some View {
        let stats = self.stats
        return List {
            Section("Özet") {
                LabeledContent("Toplam istek", value: "\(stats.totalRequests)")
                LabeledContent("Hata", value: "\(stats.failureCount) (%\(stats.failurePercent))")
                if stats.cancelledCount > 0 {
                    LabeledContent("İptal", value: "\(stats.cancelledCount)")
                }
                if let ms = stats.averageDurationMs { LabeledContent("Ortalama süre", value: "\(ms) ms") }
                if let ms = stats.medianDurationMs { LabeledContent("Medyan süre", value: "\(ms) ms") }
                if let ms = stats.p95DurationMs { LabeledContent("p95 süre", value: "\(ms) ms") }
                LabeledContent("İstek boyutu", value: Formatting.byteCount(stats.totalRequestBytes))
                LabeledContent("Yanıt boyutu", value: Formatting.byteCount(stats.totalResponseBytes))
            }

            if !stats.statusClassCounts.isEmpty {
                Section("Durum dağılımı") {
                    ForEach(stats.statusClassCounts, id: \.name) { item in
                        barRow(name: item.name, count: item.count,
                               maxCount: stats.totalRequests, color: statusColor(item.name))
                    }
                }
            }

            if !stats.methodCounts.isEmpty {
                Section("Metotlar") {
                    ForEach(stats.methodCounts, id: \.name) { item in
                        barRow(name: item.name, count: item.count,
                               maxCount: stats.methodCounts.first?.count ?? 1, color: .accentColor)
                    }
                }
            }

            if !stats.slowest.isEmpty {
                Section("En yavaş istekler") {
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
                Section("Host'lar") {
                    ForEach(stats.hostCounts, id: \.name) { item in
                        barRow(name: item.name, count: item.count,
                               maxCount: stats.hostCounts.first?.count ?? 1, color: .teal)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Yardımcılar

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
        case "5xx", "Hata": return .red
        default: return .gray
        }
    }
}
#endif

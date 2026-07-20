#if canImport(UIKit)
import SwiftUI

/// Aktif mock'ların listesi: görüntüle, tek tek (kaydırarak) veya toptan kaldır.
/// Yeni mock, bir network kaydının detayındaki **"Mock'a çevir"** ile eklenir.
struct MockListView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var mocks: [OlafMockResponse] = OlafNetwork.activeMocks

    var body: some View {
        NavigationStack {
            Group {
                if mocks.isEmpty {
                    ContentUnavailableView(
                        "Mock yok",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Bir network kaydının detayından \"Mock'a çevir\" ile ekleyin; eşleşen istekler ağa çıkmadan o yanıtı alır.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(mocks) { mock in
                                row(mock)
                            }
                            .onDelete(perform: delete)
                        } footer: {
                            Text("Birden çok mock eşleşirse ilk eklenen kazanır. Mock'lar uygulama yeniden başlayınca sıfırlanır.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Mock'lar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Tümünü kaldır", role: .destructive) {
                        OlafNetwork.removeAllMocks()
                        mocks = []
                    }
                    .disabled(mocks.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
            .onAppear { mocks = OlafNetwork.activeMocks }
        }
    }

    private func row(_ mock: OlafMockResponse) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                MethodBadge(method: mock.method ?? "TÜMÜ")
                Text(mock.urlContains)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                if let errorCode = mock.transportError {
                    Text("Taşıma hatası (\(errorCode.rawValue))")
                        .foregroundStyle(.red)
                } else {
                    Text("→ \(mock.statusCode)")
                    if !mock.body.isEmpty {
                        Text("· \(Formatting.byteCount(mock.body.count))")
                    }
                }
                if mock.delaySeconds > 0 {
                    Text("· \(String(format: "%.1f", mock.delaySeconds)) sn gecikme")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            OlafNetwork.removeMock(id: mocks[index].id)
        }
        mocks = OlafNetwork.activeMocks
    }
}
#endif

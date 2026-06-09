#if canImport(UIKit)
import SwiftUI
import OlafCore
import OlafUpload

/// Bug rapor ekranı (SwiftUI). Banner'daki **Evet**'te present edilir.
///
/// - 2 alan: **"Ne yaşadın?"** → `whatHappened`, **"Ne olmalıydı?"** → `whatExpected`.
/// - İlk kullanımda (saklı isim yoksa) **isim** alanı da gösterilir (tek seferlik).
/// - **Gönder** butonu: iki içerik alanı (trim sonrası) ve gerekiyorsa isim dolu ise aktif.
/// - Gönder → loading → upload → başarıda kapanır + "Gönderildi" toast; hata → inline + retry.
@MainActor
struct BugReportSheet: View {

    enum SubmitState: Equatable {
        case idle
        case sending
        case failed(String)
    }

    /// Klavye/odak sırası için alanlar.
    private enum Field: Hashable {
        case name, happened, expected
    }

    let screenshot: UIImage?
    /// Sheet kapanırken (başarılı gönderim sonrası) çağrılır.
    let onClose: (_ didSend: Bool) -> Void

    @State private var whatHappened: String = ""
    @State private var whatExpected: String = ""
    @State private var testerName: String = ""
    @State private var state: SubmitState = .idle
    @FocusState private var focusedField: Field?

    private let requiresName: Bool = !OlafDeviceIdentity.hasStoredName

    /// Görünen alanların odak sırası (isim yalnızca ilk seferde vardır).
    private var fieldOrder: [Field] {
        (requiresName ? [Field.name] : []) + [.happened, .expected]
    }

    private var isLastFieldFocused: Bool {
        guard let f = focusedField, let i = fieldOrder.firstIndex(of: f) else { return false }
        return i == fieldOrder.count - 1
    }

    /// Sonraki alana geç; son alandaysa klavyeyi kapat.
    private func focusNext() {
        guard let f = focusedField, let i = fieldOrder.firstIndex(of: f) else {
            focusedField = fieldOrder.first
            return
        }
        focusedField = (i + 1 < fieldOrder.count) ? fieldOrder[i + 1] : nil
    }

    private var trimmedHappened: String { whatHappened.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedExpected: String { whatExpected.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { testerName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        guard !trimmedHappened.isEmpty, !trimmedExpected.isEmpty else { return false }
        if requiresName, trimmedName.isEmpty { return false }
        return state != .sending
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let screenshot {
                            previewSection(screenshot)
                        }
                        if requiresName {
                            nameSection.id(Field.name)
                        }
                        fieldSection(
                            title: "Ne yaşadın?",
                            placeholder: "Karşılaştığın sorunu anlat…",
                            text: $whatHappened,
                            field: .happened
                        )
                        .id(Field.happened)
                        fieldSection(
                            title: "Ne olmalıydı?",
                            placeholder: "Beklediğin doğru davranış neydi?",
                            text: $whatExpected,
                            field: .expected
                        )
                        .id(Field.expected)
                        if case let .failed(message) = state {
                            errorBanner(message)
                        }
                        // Klavyenin son alanı örtmemesi için alt boşluk.
                        Color.clear.frame(height: 8)
                    }
                    .padding(20)
                }
                // Odak değişince odaklanan alanı klavyenin üstüne kaydır.
                .onChange(of: focusedField) { _, newValue in
                    guard let f = newValue else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(f, anchor: .center)
                    }
                }
            }
            .navigationTitle("Sorun Bildir")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { onClose(false) }
                        .disabled(state == .sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    sendButton
                }
                // Klavye üstü gezinme: son alanda "Bitti", değilse "Sonraki".
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if isLastFieldFocused {
                        Button("Bitti") { focusedField = nil }
                    } else {
                        Button("Sonraki") { focusNext() }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(state == .sending)
    }

    // MARK: - Sections

    private func previewSection(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Spacer()
            }
            screenshotConsentNotice
        }
    }

    /// Bilgilendirilmiş onay: ekran görüntüsünün ekrandaki TÜM bilgileri (hassas veriler dahil)
    /// içerebileceği ve hassas veri varsa gönderilmemesi gerektiği konusunda kullanıcıyı uyarır.
    private var screenshotConsentNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ekran görüntüsü hakkında")
                    .font(.subheadline.weight(.semibold))
                Text("Bu ekran görüntüsü, gönderdiğinizde ekranda görünen TÜM bilgileri (bakiye, hesap/kart bilgileri, kişisel veriler dahil) içerir. Ekranda hassas veri varsa lütfen raporu göndermeyin veya önce o ekrandan çıkın. Görüntü, rapor ile birlikte yüklenir.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adın")
                .font(.headline)
            TextField("Adını gir (yalnızca ilk seferde sorulur)", text: $testerName)
                .textFieldStyle(.roundedBorder)
                .disabled(state == .sending)
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusNext() }
        }
    }

    private func fieldSection(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: text)
                    .frame(minHeight: 96)
                    .disabled(state == .sending)
                    .focused($focusedField, equals: field)
            }
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Gönderilemedi")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Tekrar 'Gönder'e basabilirsin; başarısız olursa rapor kuyruğa alınır ve daha sonra otomatik gönderilir.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sendButton: some View {
        Group {
            if state == .sending {
                ProgressView()
            } else {
                Button("Gönder") { submit() }
                    .disabled(!canSend)
            }
        }
    }

    // MARK: - Submit

    private func submit() {
        guard canSend else { return }
        state = .sending
        let name = requiresName ? trimmedName : nil
        Task {
            let didSend = await BugReportComposer.send(
                whatHappened: trimmedHappened,
                whatExpected: trimmedExpected,
                testerName: name,
                screenshot: screenshot
            )
            await MainActor.run {
                if didSend {
                    onClose(true)
                } else {
                    state = .failed("Sunucuya ulaşılamadı.")
                }
            }
        }
    }
}
#endif

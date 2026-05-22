#if canImport(UIKit)
import SwiftUI
import UIKit

/// Panoya kopyalar + haptic geri bildirim verir + verilen bayrağı kısa süre `true` yapar
/// (toast göstermek için).
@MainActor
func logFoxCopy(_ text: String, showing flag: Binding<Bool>) {
    UIPasteboard.general.string = text
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    flag.wrappedValue = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
        flag.wrappedValue = false
    }
}

/// "Kopyalandı" toast'unu altta gösteren modifier.
private struct CopyToastModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    Label("Kopyalandı", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.95), in: Capsule())
                        .shadow(radius: 6, y: 2)
                        .padding(.bottom, 44)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
    }
}

extension View {
    /// "Kopyalandı" toast geri bildirimi.
    func copyToast(_ isPresented: Binding<Bool>) -> some View {
        modifier(CopyToastModifier(isPresented: isPresented))
    }
}
#endif

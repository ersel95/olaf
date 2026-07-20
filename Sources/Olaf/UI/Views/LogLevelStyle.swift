#if canImport(UIKit)
import SwiftUI

extension LogLevel {
    /// Viewer'da seviyeyi ayırt etmek için renk.
    var color: Color {
        switch self {
        case .trace: return .gray
        case .debug: return .secondary
        case .info: return .blue
        case .notice: return .teal
        case .warning: return .orange
        case .error: return .red
        case .critical: return .pink
        }
    }
}

extension LogEntry {
    /// Liste/detayda kopyalanabilir tek satır temsil.
    var oneLineDescription: String {
        PlainTextFormatter().string(from: self)
    }
}
#endif

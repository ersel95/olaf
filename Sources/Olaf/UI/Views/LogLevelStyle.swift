#if canImport(UIKit)
import SwiftUI

extension LogLevel {
    /// Color used to distinguish the level in the viewer.
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
    /// A single-line, copyable representation for the list/detail view.
    var oneLineDescription: String {
        PlainTextFormatter().string(from: self)
    }
}
#endif

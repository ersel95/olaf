#if canImport(UIKit)
import SwiftUI

/// Colored pill for the HTTP status code / error.
struct StatusPill: View {
    let statusCode: Int?
    let isFailure: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var text: String {
        if let statusCode { return String(statusCode) }
        return isFailure ? "ERR" : "•••"
    }

    private var color: Color {
        if isFailure { return .red }
        guard let statusCode else { return .gray }
        switch statusCode {
        case 200..<300: return .green
        case 300..<400: return .teal
        case 400..<500: return .orange
        default: return .red
        }
    }
}

/// HTTP method badge (monospace).
struct MethodBadge: View {
    let method: String

    var body: some View {
        Text(method.uppercased())
            .font(.caption2.weight(.semibold).monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Colored dot on the left for the log level.
struct LevelDot: View {
    let level: LogLevel
    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: 8, height: 8)
    }
}
#endif

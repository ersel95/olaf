#if canImport(UIKit)
import SwiftUI

// iOS 15 back-ports of the SwiftUI building blocks the viewer uses. Each one defers to the
// native API where it exists, so iOS 16/17+ behavior is unchanged.

/// `NavigationStack` on iOS 16+, a stack-style `NavigationView` on iOS 15.
struct CompatNavigationStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 16, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

/// `ContentUnavailableView` on iOS 17+, an equivalent centered stack on iOS 15/16.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var description: Text?

    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        if #available(iOS 17, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: description)
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.weight(.bold))
                description?
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// `LabeledContent` look-alike (label leading, secondary-styled value trailing) that also
/// runs on iOS 15. Mirrors the three `LabeledContent` initializers the viewer uses.
struct LabeledRow<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            label
            Spacer(minLength: 12)
            content
                .foregroundStyle(.secondary)
        }
    }
}

extension LabeledRow where Label == Text {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

extension LabeledRow where Label == Text, Content == Text {
    init(_ title: String, value: String) {
        self.init(content: { Text(value) }) { Text(title) }
    }
}
#endif

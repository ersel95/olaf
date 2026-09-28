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

/// `LabeledContent` on iOS 16+; on iOS 15 a look-alike (label leading, value trailing).
/// Mirrors the three `LabeledContent` initializers the viewer uses. Only the plain
/// `value:` form dims its value on iOS 15, so custom content (e.g. a `TextField`) keeps its
/// own color there — callers that want a dimmed custom value style it themselves.
struct LabeledRow<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content
    private var dimsContent = false

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16, *) {
            LabeledContent { content } label: { label }
        } else {
            HStack(alignment: .firstTextBaseline) {
                label
                Spacer(minLength: 12)
                if dimsContent {
                    content.foregroundStyle(.secondary)
                } else {
                    content
                }
            }
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
        dimsContent = true
    }
}

extension View {
    /// `navigationDestination(for:)` on iOS 16+; a no-op on iOS 15, where links carry
    /// their destination directly (see `CompatNavigationLink`).
    @ViewBuilder
    func compatNavigationDestination<D: Hashable, Destination: View>(
        for type: D.Type,
        @ViewBuilder destination: @escaping (D) -> Destination
    ) -> some View {
        if #available(iOS 16, *) {
            navigationDestination(for: type, destination: destination)
        } else {
            self
        }
    }
}

/// Value-based `NavigationLink` on iOS 16+ (resolved by `compatNavigationDestination`), so a
/// pushed detail survives its row leaving the list; destination-based on iOS 15.
struct CompatNavigationLink<Value: Hashable, Destination: View, Label: View>: View {
    let value: Value
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Label

    var body: some View {
        if #available(iOS 16, *) {
            NavigationLink(value: value, label: label)
        } else {
            NavigationLink(destination: destination, label: label)
        }
    }
}
#endif

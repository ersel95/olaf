#if canImport(UIKit)
import SwiftUI

/// Horizontal filter bar with category chips. Shows "all" when nothing is selected.
struct FilterBarView: View {
    @ObservedObject var model: LogViewerModel

    var body: some View {
        let categories = model.availableCategories
        if !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        chip(category)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
    }

    private func chip(_ category: LogCategory) -> some View {
        let isSelected = model.selectedCategories.contains(category)
        return Button {
            model.toggleCategory(category)
        } label: {
            Text(category.rawValue)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
#endif

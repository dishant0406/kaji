import SwiftUI

struct SearchableListPicker<Item: Identifiable, RowContent: View>: View {
    let items: [Item]
    let filterKey: (Item) -> String
    let placeholder: String
    let emptyLabel: String
    let onSelect: (Item) -> Void
    @ViewBuilder let row: (Item, Bool) -> RowContent

    @State private var searchText = ""
    @State private var highlightedIndex: Int?

    private var filteredItems: [Item] {
        guard !searchText.isEmpty else { return items }
        return items.filter { filterKey($0).localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                DroidIcon(systemName: "magnifyingglass", size: 12)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .accessibilityHidden(true)
                PaletteSearchField(
                    text: $searchText,
                    placeholder: placeholder,
                    fontSize: 12,
                    onSubmit: { confirmSelection() },
                    onEscape: {},
                    onArrowUp: { moveHighlight(-1) },
                    onArrowDown: { moveHighlight(1) }
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().overlay(DroidTheme.border)

            if filteredItems.isEmpty {
                Text(emptyLabel)
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                row(item, index == highlightedIndex)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(item) }
                                    .droidPointer()
                                    .id(item.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: highlightedIndex) { _, newIndex in
                        guard let newIndex, newIndex < filteredItems.count else { return }
                        proxy.scrollTo(filteredItems[newIndex].id, anchor: nil)
                    }
                }
            }
        }
        .background(
            TranslucentSurface(
                base: DroidTheme.tertiaryBackground,
                material: .menu,
                tintOpacity: 0.74
            )
        )
        .onChange(of: searchText) { highlightedIndex = filteredItems.isEmpty ? nil : 0 }
    }

    private func moveHighlight(_ delta: Int) {
        let list = filteredItems
        guard !list.isEmpty else { return }
        guard let current = highlightedIndex else {
            highlightedIndex = delta > 0 ? 0 : list.count - 1
            return
        }
        highlightedIndex = max(0, min(list.count - 1, current + delta))
    }

    private func confirmSelection() {
        let list = filteredItems
        guard let index = highlightedIndex, index < list.count else { return }
        onSelect(list[index])
    }
}

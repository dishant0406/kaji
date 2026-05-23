import SwiftUI

struct SearchableListPicker<Item: Identifiable, RowContent: View>: View {
    let items: [Item]
    let filterKey: (Item) -> String
    let placeholder: String
    let emptyLabel: String
    let emptyActionTitle: ((String) -> String?)?
    let emptyActionDetail: String?
    let onEmptyAction: ((String) -> Void)?
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
                KajiIcon(systemName: "magnifyingglass", size: 12)
                    .foregroundStyle(KajiTheme.fgMuted)
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

            Divider().overlay(KajiTheme.border)

            if filteredItems.isEmpty {
                emptyContent
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                row(item, index == highlightedIndex)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(item) }
                                    .kajiPointer()
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
                base: KajiTheme.tertiaryBackground,
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
        guard let index = highlightedIndex, index < list.count else {
            confirmEmptyAction()
            return
        }
        onSelect(list[index])
    }

    @ViewBuilder
    private var emptyContent: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title = emptyActionTitle?(query), !query.isEmpty {
            Button {
                onEmptyAction?(query)
            } label: {
                HStack(spacing: 10) {
                    KajiIcon(systemName: "plus", size: 12)
                        .foregroundStyle(KajiTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .kajiFont(size: 12, weight: .medium)
                            .foregroundStyle(KajiTheme.fg)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let emptyActionDetail {
                            Text(emptyActionDetail)
                                .kajiFont(size: 11)
                                .foregroundStyle(KajiTheme.fgMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            Spacer(minLength: 0)
        } else {
            Text(emptyLabel)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func confirmEmptyAction() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, emptyActionTitle?(query) != nil else { return }
        onEmptyAction?(query)
    }
}

import SwiftUI

struct PaletteOverlay<Item: Identifiable & Sendable>: View {
    let placeholder: String
    let emptyLabel: String
    let noMatchLabel: String
    let search: (String) async -> [Item]
    let onSelect: (Item) -> Void
    let onDismiss: () -> Void
    let row: (Item, Bool) -> AnyView

    @State private var query = ""
    @State private var results: [Item] = []
    @State private var highlightedIndex: Int? = 0
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            KajiTheme.bg.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                searchField
                Divider().overlay(KajiTheme.border.opacity(0.75))
                resultsList
            }
            .frame(width: 580, height: 420)
            .background(KajiTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: KajiShape.modalRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.modalRadius)
                    .stroke(KajiTheme.borderStrong.opacity(0.82), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear {
            performSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: "magnifyingglass", size: 12)
                .foregroundStyle(KajiTheme.fgDim)
                .accessibilityHidden(true)

            PaletteSearchField(
                text: $query,
                placeholder: placeholder,
                fontSize: 14,
                onSubmit: confirmSelection,
                onEscape: onDismiss,
                onArrowUp: { moveHighlight(-1) },
                onArrowDown: { moveHighlight(1) }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(KajiTheme.bg)
        .onChange(of: query) {
            performSearch()
        }
    }

    private var resultsList: some View {
        Group {
            if results.isEmpty {
                VStack {
                    Spacer()
                    Text(query.isEmpty ? emptyLabel : noMatchLabel)
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgDim)
                    Spacer()
                }
            } else {
                VirtualizedList(items: results, rowHeight: 52, highlightedIndex: highlightedIndex) { index, item in
                    row(item, index == highlightedIndex)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(item) }
                        .kajiPointer()
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func performSearch() {
        searchTask?.cancel()
        let currentQuery = query

        searchTask = Task {
            let found = await search(currentQuery)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                results = found
                highlightedIndex = found.isEmpty ? nil : min(highlightedIndex ?? 0, found.count - 1)
            }
        }
    }

    private func moveHighlight(_ delta: Int) {
        guard !results.isEmpty else { return }
        guard let highlightedIndex else {
            self.highlightedIndex = delta > 0 ? 0 : results.count - 1
            return
        }
        self.highlightedIndex = max(0, min(results.count - 1, highlightedIndex + delta))
    }

    private func confirmSelection() {
        guard let highlightedIndex, highlightedIndex < results.count else { return }
        onSelect(results[highlightedIndex])
    }
}

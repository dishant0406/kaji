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
            DroidTheme.bg.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                searchField
                Divider().overlay(DroidTheme.border.opacity(0.75))
                resultsList
            }
            .frame(width: 580, height: 420)
            .background(DroidTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: DroidShape.modalRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.modalRadius)
                    .stroke(DroidTheme.borderStrong.opacity(0.82), lineWidth: 1)
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
            DroidIcon(systemName: "magnifyingglass", size: 12)
                .foregroundStyle(DroidTheme.fgDim)
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
        .background(DroidTheme.bg)
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
                        .droidFont(size: 12)
                        .foregroundStyle(DroidTheme.fgDim)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, index == highlightedIndex)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(item) }
                                    .id(item.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: highlightedIndex) { _, newIndex in
                        guard let newIndex, newIndex < results.count else { return }
                        proxy.scrollTo(results[newIndex].id, anchor: .center)
                    }
                }
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

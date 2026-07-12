import Reorderable
import SwiftUI

struct BrowserTabStrip: View {
    private static let addButtonWidth: CGFloat = 32

    @Bindable var state: BrowserPaneState
    @Binding var pendingURL: String
    let onClosePane: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isReordering = false

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    tabRow(availableWidth: geometry.size.width)
                        .frame(minWidth: geometry.size.width, alignment: .leading)
                }
                .autoScrollOnEdges()
                .onChange(of: state.selectedPageID) { _, selectedPageID in
                    withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(selectedPageID, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 42)
        .background(KajiTheme.secondaryBackground)
    }

    private func tabRow(availableWidth: CGFloat) -> some View {
        let tabWidth = BrowserTabWidthPolicy.width(
            availableWidth: availableWidth,
            tabCount: state.pages.count,
            trailingWidth: Self.addButtonWidth
        )

        return HStack(spacing: 0) {
            ReorderableHStack(
                state.pages.map { BrowserTabItem(page: $0) },
                onMove: { source, destination in
                    state.reorderPage(from: source, to: destination)
                },
                onDragStateChange: { dragging in
                    isReordering = dragging
                },
                content: { item, isDragged in
                    BrowserTabButton(
                        page: item.page,
                        selected: item.page.id == state.selectedPageID,
                        isDragged: isDragged,
                        isAnyDragging: isReordering,
                        onSelect: { selectPage(item.page) },
                        onClose: { closePage(item.page.id) }
                    )
                    .frame(width: tabWidth)
                    .id(item.id)
                }
            )

            BrowserTabAddButton(action: openPage)
                .frame(width: Self.addButtonWidth, height: 34)
                .attachedShortcutHint(for: .browserNewPage)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func selectPage(_ page: BrowserPageState) {
        state.selectPage(id: page.id)
        pendingURL = page.url
    }

    private func openPage() {
        let page = state.openPage()
        pendingURL = page.url
        state.controllers.controller(for: page.id).ensureStarted(url: page.url)
    }

    private func closePage(_ pageID: UUID) {
        guard state.pages.count > 1 else {
            state.controllers.closeAll()
            onClosePane()
            return
        }
        state.closePage(id: pageID)
        pendingURL = state.url
    }
}

private struct BrowserTabItem: Identifiable {
    let page: BrowserPageState

    var id: UUID {
        page.id
    }
}

private struct BrowserTabAddButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(hovered ? KajiTheme.surface : KajiTheme.bg)
                KajiIcon(systemName: "plus", size: 11)
                    .foregroundStyle(hovered ? KajiTheme.fg : KajiTheme.fgMuted)
            }
            .overlay {
                Rectangle()
                    .strokeBorder(KajiTheme.border.opacity(hovered ? 0.75 : 0.35), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .kajiHoverEffect(isActive: hovered, scale: 1.04)
        .kajiChangeFeedback(KajiMotion.tapFeedback, value: hovered, isEnabled: hovered)
        .kajiPointer()
        .help("New browser tab")
        .accessibilityLabel("New browser tab")
    }
}

private enum BrowserTabWidthPolicy {
    static let minimum: CGFloat = 96
    static let maximum: CGFloat = 180

    static func width(availableWidth: CGFloat, tabCount: Int, trailingWidth: CGFloat) -> CGFloat {
        let count = max(tabCount, 1)
        let usableWidth = max(0, availableWidth - trailingWidth - 20)
        let idealWidth = usableWidth / CGFloat(count)
        return max(minimum, min(maximum, idealWidth))
    }
}

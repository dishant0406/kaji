import Reorderable
import SwiftUI

struct BrowserTabButton: View {
    @Bindable var page: BrowserPageState
    let selected: Bool
    let isDragged: Bool
    let isAnyDragging: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            titleArea
            closeButton
            Rectangle()
                .fill(KajiTheme.border.opacity(0.55))
                .frame(width: 1)
        }
        .frame(height: 34)
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            if selected {
                Rectangle()
                    .fill(KajiTheme.accent)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            Rectangle()
                .strokeBorder(KajiTheme.border.opacity(selected || hovered ? 0.75 : 0.35), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .opacity(isDragged ? 0.94 : 1)
        .scaleEffect(isDragged ? 1.015 : 1)
        .zIndex(isDragged ? 10 : 0)
        .onHover { hovering in
            guard !isAnyDragging else { return }
            hovered = hovering
        }
        .onChange(of: isAnyDragging) { _, dragging in
            if dragging { hovered = false }
        }
        .animation(KajiMotion.fast, value: selected)
        .animation(KajiMotion.hover, value: hovered)
        .animation(KajiMotion.select, value: isDragged)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: selected, isEnabled: selected)
        .kajiPointer()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
    }

    private var titleArea: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "globe", size: 12)
                .foregroundStyle(selected ? KajiTheme.fg : KajiTheme.fgMuted)

            Text(page.title)
                .kajiFont(size: 12, weight: selected ? .semibold : .regular)
                .foregroundStyle(selected ? KajiTheme.fg : KajiTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isAnyDragging else { return }
            onSelect()
        }
        .dragHandle()
    }

    private var closeButton: some View {
        Button(action: onClose) {
            KajiIcon(systemName: "xmark", size: 9)
                .foregroundStyle(hovered || selected ? KajiTheme.fgDim : KajiTheme.fgDim.opacity(0.7))
                .frame(width: 26, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovered || selected ? 1 : 0.68)
        .kajiPointer()
        .help("Close tab")
        .accessibilityLabel("Close tab")
    }

    private var backgroundColor: Color {
        if selected { return KajiTheme.surface }
        if hovered { return KajiTheme.hover }
        return KajiTheme.bg
    }
}

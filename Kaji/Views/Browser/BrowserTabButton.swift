import SwiftUI

struct BrowserTabButton: View {
    private static let compactWidth: CGFloat = 72
    private static let minWidth: CGFloat = 96
    private static let maxWidth: CGFloat = 180

    @Bindable var page: BrowserPageState
    let selected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var width: CGFloat = maxWidth

    private var compact: Bool {
        width <= Self.compactWidth
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(page.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? KajiTheme.fg : KajiTheme.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                closeButton
            }
            .padding(.leading, compact ? 8 : 10)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(widthReader)
        }
        .buttonStyle(.plain)
        .kajiPointer()
        .frame(height: 28)
        .frame(minWidth: Self.minWidth, maxWidth: Self.maxWidth)
        .background(selected ? KajiTheme.surface : KajiTheme.bg, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border))
        .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .animation(KajiMotion.fast, value: selected)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: selected, isEnabled: selected)
        .kajiPointer()
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .kajiPointer()
        .help("Close tab")
        .accessibilityLabel("Close tab")
    }

    private var widthReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { width = geometry.size.width }
                .onChange(of: geometry.size.width) { _, newValue in width = newValue }
        }
    }
}

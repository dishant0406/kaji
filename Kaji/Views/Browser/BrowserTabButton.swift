import SwiftUI

struct BrowserTabButton: View {
    @Bindable var page: BrowserPageState
    let selected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                Text(page.title)
                    .lineLimit(1)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? KajiTheme.fg : KajiTheme.fgMuted)
                    .frame(maxWidth: 140, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .buttonStyle(.plain)
            .kajiPointer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .help("Close tab")
        }
        .frame(height: 28)
        .background(selected ? KajiTheme.surface : KajiTheme.bg, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border))
        .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .kajiPointer()
    }
}

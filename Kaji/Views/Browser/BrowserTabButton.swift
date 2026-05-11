import SwiftUI

struct BrowserTabButton: View {
    @Bindable var page: BrowserPageState
    let selected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(page.title)
                    .lineLimit(1)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? KajiTheme.fg : KajiTheme.fgMuted)
                    .frame(maxWidth: 140, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(KajiTheme.fgMuted)
                }
                .buttonStyle(.plain)
                .kajiPointer()
                .help("Close tab")
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(selected ? KajiTheme.surface : KajiTheme.bg, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border))
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .kajiPointer()
    }
}

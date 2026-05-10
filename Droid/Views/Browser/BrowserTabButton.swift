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
                    .foregroundStyle(selected ? DroidTheme.fg : DroidTheme.fgMuted)
                    .frame(maxWidth: 140, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DroidTheme.fgMuted)
                }
                .buttonStyle(.plain)
                .droidPointer()
                .help("Close tab")
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(selected ? DroidTheme.surface : DroidTheme.bg, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            .overlay(RoundedRectangle(cornerRadius: DroidShape.tileRadius).stroke(DroidTheme.border))
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.plain)
        .droidPointer()
    }
}

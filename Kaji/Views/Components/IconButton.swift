import SwiftUI

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 12
    var color: Color = KajiTheme.fgMuted
    var hoverColor: Color = KajiTheme.fg
    var selected = false
    let accessibilityLabel: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .fill(active ? KajiTheme.surface : .clear)
                KajiIcon(systemName: symbol, size: size)
                    .foregroundStyle(active ? hoverColor : color)
            }
            .frame(width: 28, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .strokeBorder(KajiTheme.border.opacity(borderOpacity), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.borderless)
        .onHover { hovered = $0 }
        .kajiPointer()
        .accessibilityLabel(accessibilityLabel)
    }

    private var active: Bool {
        isEnabled && (selected || hovered)
    }

    private var borderOpacity: Double {
        ChromeIconButtonStylePolicy.borderOpacity(active: active, isTahoe: isTahoe)
    }

    private var isTahoe: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

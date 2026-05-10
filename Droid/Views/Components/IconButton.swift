import SwiftUI

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 12
    var color: Color = DroidTheme.fgMuted
    var hoverColor: Color = DroidTheme.fg
    var selected = false
    let accessibilityLabel: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .fill(active ? DroidTheme.surface : .clear)
                DroidIcon(systemName: symbol, size: size)
                    .foregroundStyle(active ? hoverColor : color)
            }
            .frame(width: 28, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .strokeBorder(DroidTheme.border.opacity(borderOpacity), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.borderless)
        .onHover { hovered = $0 }
        .droidPointer()
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

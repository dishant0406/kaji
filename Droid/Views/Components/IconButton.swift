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

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .fill(selected || hovered ? DroidTheme.surface : .clear)
                DroidIcon(systemName: symbol, size: size)
                    .foregroundStyle(selected || hovered ? hoverColor : color)
            }
            .frame(width: 28, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .strokeBorder(selected || hovered ? DroidTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

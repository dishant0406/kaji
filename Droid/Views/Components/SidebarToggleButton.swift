import SwiftUI

struct SidebarToggleButton: View {
    let expanded: Bool
    let accessibilityLabel: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .fill(hovered ? DroidTheme.surface : .clear)
                SidebarToggleGlyph(expanded: expanded)
                    .foregroundStyle(hovered ? DroidTheme.fg : DroidTheme.fgMuted)
            }
            .frame(width: 28, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .strokeBorder(hovered ? DroidTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SidebarToggleGlyph: View {
    let expanded: Bool

    var body: some View {
        ZStack(alignment: expanded ? .leading : .trailing) {
            RoundedRectangle(cornerRadius: 3)
                .stroke(lineWidth: 1.4)
                .frame(width: 15, height: 13)
            Rectangle()
                .frame(width: 1.2, height: 9)
                .padding(expanded ? .leading : .trailing, 4)
            Image(systemName: expanded ? "chevron.left" : "chevron.right")
                .font(.system(size: 6, weight: .bold))
                .padding(expanded ? .leading : .trailing, 7)
        }
        .frame(width: 17, height: 15)
    }
}

import SwiftUI

struct SidebarUpdateButton: View {
    let version: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            KajiIcon(systemName: "arrow.down.circle.fill", size: 13)
                .foregroundStyle(hovered ? KajiTheme.accent : KajiTheme.fgMuted)
                .frame(width: 28, height: 28)
                .background(background, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                        .strokeBorder(hovered ? KajiTheme.border : .clear, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Update available: \(version)")
        .accessibilityLabel("Update available")
        .accessibilityValue(version)
    }

    private var background: Color {
        hovered ? KajiTheme.surface : .clear
    }
}

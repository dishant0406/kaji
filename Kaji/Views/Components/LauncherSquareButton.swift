import SwiftUI

struct LauncherSquareButton: View {
    let iconName: String
    let accessibilityLabel: String
    var helpText: String?
    var iconSize: CGFloat = 14
    var frameSize: CGFloat = 28
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            CLILauncherIcon(
                iconName: iconName,
                size: iconSize,
                color: foregroundColor
            )
            .frame(width: frameSize, height: frameSize)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .kajiHoverEffect(isActive: hovered)
        .kajiPointer()
        .accessibilityLabel(accessibilityLabel)
        .help(helpText ?? accessibilityLabel)
    }

    private var foregroundColor: Color {
        hovered ? KajiTheme.fg : KajiTheme.fgMuted
    }

    private var backgroundColor: Color {
        hovered ? KajiTheme.surface : KajiTheme.secondaryBackground
    }

    private var borderColor: Color {
        hovered ? KajiTheme.border : .clear
    }
}

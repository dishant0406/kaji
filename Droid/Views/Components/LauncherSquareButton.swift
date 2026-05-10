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
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .droidPointer()
        .accessibilityLabel(accessibilityLabel)
        .help(helpText ?? accessibilityLabel)
    }

    private var foregroundColor: Color {
        hovered ? DroidTheme.fg : DroidTheme.fgMuted
    }

    private var backgroundColor: Color {
        hovered ? DroidTheme.surface : DroidTheme.secondaryBackground
    }

    private var borderColor: Color {
        hovered ? DroidTheme.border : .clear
    }
}

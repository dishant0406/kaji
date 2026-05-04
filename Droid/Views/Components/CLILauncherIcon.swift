import SwiftUI

struct CLILauncherIcon: View {
    let iconName: String
    let size: CGFloat
    var color: Color = DroidTheme.fgMuted

    var body: some View {
        if iconName == "terminal" {
            TerminalLauncherIcon(size: size, color: color)
        } else if ProviderIconView.hasIcon(named: iconName) {
            ProviderIconView(
                iconName: iconName,
                size: size,
                style: ["opencode", "pi"].contains(iconName) ? .colored : .monochrome(color)
            )
        } else {
            DroidIcon(systemName: iconName, size: size)
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }
}

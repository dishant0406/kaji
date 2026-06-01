import SwiftUI

struct CLILauncherIcon: View {
    let iconName: String
    let size: CGFloat
    var color: Color = KajiTheme.fgMuted

    var body: some View {
        if iconName == "terminal" {
            TerminalLauncherIcon(size: size, color: color)
        } else if iconName == "kaji" {
            KajiLogo(size: size)
        } else if ProviderIconView.hasIcon(named: iconName) {
            ProviderIconView(
                iconName: iconName,
                size: size,
                style: ["opencode", "pi"].contains(iconName) ? .colored : .monochrome(color)
            )
        } else {
            KajiIcon(systemName: iconName, size: size)
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }
}

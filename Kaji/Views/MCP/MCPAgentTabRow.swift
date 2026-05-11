import SwiftUI

struct MCPAgentTabRow: View {
    let panel: MCPAgentPanelState
    let selected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                CLILauncherIcon(iconName: panel.agent.iconName, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(panel.agent.displayName)
                        .kajiFont(size: 12, weight: selected ? .semibold : .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text("\(count) servers")
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                Spacer(minLength: 0)
                if panel.errorMessage != nil {
                    KajiIcon(systemName: "exclamationmark.triangle", size: 11)
                        .foregroundStyle(KajiTheme.diffRemoveFg)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(selected ? KajiTheme.surface : .clear, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .stroke(selected ? KajiTheme.border : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .kajiPointer()
    }
}

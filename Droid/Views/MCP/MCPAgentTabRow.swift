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
                        .droidFont(size: 12, weight: selected ? .semibold : .medium)
                        .foregroundStyle(DroidTheme.fg)
                    Text("\(count) servers")
                        .droidFont(size: 10)
                        .foregroundStyle(DroidTheme.fgDim)
                }
                Spacer(minLength: 0)
                if panel.errorMessage != nil {
                    DroidIcon(systemName: "exclamationmark.triangle", size: 11)
                        .foregroundStyle(DroidTheme.diffRemoveFg)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(selected ? DroidTheme.surface : .clear, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .stroke(selected ? DroidTheme.border : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

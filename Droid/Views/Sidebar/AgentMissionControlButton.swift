import SwiftUI

struct AgentMissionControlButton: View {
    let items: [AgentMissionControlItem]
    let expanded: Bool
    let action: () -> Void
    @State private var hovered = false

    private var needsAttention: Bool {
        items.contains { $0.status == .needsAttention || $0.status == .failed }
    }

    private var hasRunning: Bool {
        items.contains { $0.status == .running }
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .fill(background)
                HStack(spacing: 6) {
                    DroidIcon(systemName: iconName, size: 12)
                        .foregroundStyle(foreground)
                    if expanded {
                        Text("Agents")
                            .droidFont(size: 11, weight: .medium)
                            .foregroundStyle(foreground)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !items.isEmpty {
                    Text("\(min(items.count, 9))")
                        .droidFont(size: 9, weight: .semibold)
                        .foregroundStyle(DroidTheme.bg)
                        .frame(width: 13, height: 13)
                        .background(badgeColor, in: Circle())
                        .padding(1)
                }
            }
            .frame(width: expanded ? 78 : 28, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .strokeBorder(hovered || !items.isEmpty ? DroidTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Agents")
    }

    private var iconName: String {
        needsAttention ? "exclamationmark.bubble" : "rectangle.stack"
    }

    private var foreground: Color {
        if needsAttention { return DroidTheme.diffHunkFg }
        if hasRunning { return DroidTheme.fg }
        return hovered ? DroidTheme.fg : DroidTheme.fgMuted
    }

    private var background: Color {
        if hovered { return DroidTheme.surface }
        if hasRunning || needsAttention { return DroidTheme.surface.opacity(0.68) }
        return .clear
    }

    private var badgeColor: Color {
        needsAttention ? DroidTheme.diffHunkFg : DroidTheme.accent
    }
}

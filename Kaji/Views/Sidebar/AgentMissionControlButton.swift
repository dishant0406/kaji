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
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .fill(background)
                HStack(spacing: 6) {
                    KajiIcon(systemName: iconName, size: 12)
                        .foregroundStyle(foreground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !items.isEmpty {
                    Text("\(min(items.count, 9))")
                        .kajiFont(size: 9, weight: .semibold)
                        .foregroundStyle(KajiTheme.bg)
                        .frame(width: 13, height: 13)
                        .background(badgeColor, in: Circle())
                        .padding(1)
                }
            }
            .frame(width: 28, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .strokeBorder(hovered || !items.isEmpty ? KajiTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Agents")
    }

    private var iconName: String {
        needsAttention ? "exclamationmark.bubble" : "rectangle.stack"
    }

    private var foreground: Color {
        if needsAttention { return KajiTheme.diffHunkFg }
        if hasRunning { return KajiTheme.fg }
        return hovered ? KajiTheme.fg : KajiTheme.fgMuted
    }

    private var background: Color {
        if hovered { return KajiTheme.surface }
        if hasRunning || needsAttention { return KajiTheme.surface.opacity(0.68) }
        return .clear
    }

    private var badgeColor: Color {
        needsAttention ? KajiTheme.diffHunkFg : KajiTheme.accent
    }
}

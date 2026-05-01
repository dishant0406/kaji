import SwiftUI

enum DroidBadgeVariant {
    case neutral
    case accent
    case warning
    case danger
}

struct DroidBadge: View {
    let text: String
    var variant: DroidBadgeVariant = .neutral

    var body: some View {
        Text(text)
            .droidFont(size: 10, weight: .medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(border, lineWidth: 1)
            }
    }

    private var foreground: Color {
        switch variant {
        case .neutral:
            DroidTheme.fgMuted
        case .accent:
            DroidTheme.fg
        case .warning:
            DroidTheme.diffHunkFg
        case .danger:
            DroidTheme.diffRemoveFg
        }
    }

    private var background: Color {
        switch variant {
        case .neutral:
            DroidTheme.surface.opacity(0.42)
        case .accent:
            DroidTheme.accentSoft.opacity(0.8)
        case .warning:
            DroidTheme.diffHunkBg.opacity(0.9)
        case .danger:
            DroidTheme.diffRemoveBg.opacity(0.9)
        }
    }

    private var border: Color {
        switch variant {
        case .neutral:
            DroidTheme.border.opacity(0.7)
        case .accent:
            DroidTheme.accent.opacity(0.32)
        case .warning:
            DroidTheme.diffHunkFg.opacity(0.28)
        case .danger:
            DroidTheme.diffRemoveFg.opacity(0.32)
        }
    }
}

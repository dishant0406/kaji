import Pow
import SwiftUI

enum KajiBadgeVariant {
    case neutral
    case accent
    case warning
    case danger
}

struct KajiBadge: View {
    let text: String
    var variant: KajiBadgeVariant = .neutral

    var body: some View {
        Text(text)
            .kajiFont(size: 10, weight: .medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(border, lineWidth: 1)
            }
            .kajiChangeFeedback(feedback, value: text)
    }

    private var foreground: Color {
        switch variant {
        case .neutral:
            KajiTheme.fgMuted
        case .accent:
            KajiTheme.fg
        case .warning:
            KajiTheme.diffHunkFg
        case .danger:
            KajiTheme.diffRemoveFg
        }
    }

    private var background: Color {
        switch variant {
        case .neutral:
            KajiTheme.surface.opacity(0.42)
        case .accent:
            KajiTheme.accentSoft.opacity(0.8)
        case .warning:
            KajiTheme.diffHunkBg.opacity(0.9)
        case .danger:
            KajiTheme.diffRemoveBg.opacity(0.9)
        }
    }

    private var border: Color {
        switch variant {
        case .neutral:
            KajiTheme.border.opacity(0.7)
        case .accent:
            KajiTheme.accent.opacity(0.32)
        case .warning:
            KajiTheme.diffHunkFg.opacity(0.28)
        case .danger:
            KajiTheme.diffRemoveFg.opacity(0.32)
        }
    }

    private var feedback: AnyChangeEffect {
        switch variant {
        case .neutral:
            KajiMotion.tapFeedback
        case .accent:
            KajiMotion.selectionFeedback
        case .warning, .danger:
            KajiMotion.attentionFeedback
        }
    }
}

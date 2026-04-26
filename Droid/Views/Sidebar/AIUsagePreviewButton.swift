import SwiftUI

struct AIUsagePreviewButton: View {
    let display: (percent: Int, iconName: String)?
    let percentLabel: String?
    let expanded: Bool
    let onTap: () -> Void

    @State private var hovered = false

    private var foreground: Color {
        hovered ? DroidTheme.fg : DroidTheme.fgMuted
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if expanded {
                    expandedLabel
                } else {
                    compactLabel
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("AI Usage")
    }

    private var expandedLabel: some View {
        HStack(spacing: 4) {
            iconGlyph
            if let percentLabel {
                Text(percentLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(height: 24)
    }

    private var compactLabel: some View {
        iconGlyph
            .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private var iconGlyph: some View {
        if let display {
            ProviderIconView(iconName: display.iconName, size: 14, style: .monochrome(foreground))
        } else {
            DroidIcon(systemName: "sparkles", size: 13)
                .foregroundStyle(foreground)
        }
    }
}

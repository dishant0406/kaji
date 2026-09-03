import SwiftUI

struct ThemePickerRow: View {
    let theme: ThemePreview
    let isActive: Bool
    let onSelect: () -> Void
    let onExport: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name)
                    .kajiFont(size: 12, weight: isActive ? .semibold : .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text(theme.sourceLabel)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if hovered {
                Button("Export", action: onExport)
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
            }

            if isActive {
                KajiIcon(systemName: "checkmark", size: 10)
                    .foregroundStyle(KajiTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KajiTheme.border)
                .frame(height: 1)
        }
        .onHover { hovered = $0 }
    }

    private var backgroundColor: Color {
        if isActive {
            return KajiTheme.secondaryBackground.opacity(0.7)
        }
        if hovered {
            return KajiTheme.hover
        }
        return .clear
    }
}

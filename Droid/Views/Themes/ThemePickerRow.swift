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
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(DroidTheme.fg)
                    .lineLimit(1)
                Text(theme.sourceLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(DroidTheme.fgDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if hovered {
                Button("Export", action: onExport)
                    .buttonStyle(DroidButtonStyle(.ghost, size: .small))
            }

            if isActive {
                DroidIcon(systemName: "checkmark", size: 10)
                    .foregroundStyle(DroidTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DroidTheme.border)
                .frame(height: 1)
        }
        .onHover { hovered = $0 }
    }

    private var backgroundColor: Color {
        if isActive { return DroidTheme.secondaryBackground.opacity(0.7) }
        if hovered { return DroidTheme.hover }
        return .clear
    }
}

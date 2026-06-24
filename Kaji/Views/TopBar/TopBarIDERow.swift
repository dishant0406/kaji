import SwiftUI

struct TopBarIDERow: View {
    let ide: ExternalIDE
    let iconPath: String?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let iconPath {
                    ExternalIDEAppIcon(path: iconPath, size: 16)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ide.displayName)
                        .kajiFont(size: 12, weight: isSelected ? .semibold : .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(detail)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
                Spacer(minLength: 0)
                if isSelected {
                    KajiIcon(systemName: "checkmark", size: 10)
                        .foregroundStyle(KajiTheme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .animation(KajiMotion.fast, value: hovered)
        .animation(KajiMotion.fast, value: isSelected)
    }

    private var detail: String {
        switch ide.source {
        case .builtIn:
            "Open active worktree"
        case .custom:
            "Custom application"
        }
    }

    private var rowBackground: Color {
        if isSelected { return KajiTheme.accentSoft }
        if hovered { return KajiTheme.surface }
        return .clear
    }
}

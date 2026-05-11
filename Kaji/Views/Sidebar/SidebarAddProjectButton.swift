import SwiftUI

struct SidebarAddProjectButton: View {
    let expanded: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            if expanded {
                expandedLayout
            } else {
                collapsedLayout
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Add Project")
    }

    private var collapsedLayout: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .fill(hovered ? KajiTheme.hover : Color.clear)
            KajiIcon(systemName: "plus", size: 14)
                .foregroundStyle(hovered ? KajiTheme.fg : KajiTheme.fgMuted)
        }
        .frame(width: 36, height: 36)
    }

    private var expandedLayout: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: KajiShape.controlRadius)
                    .fill(hovered ? KajiTheme.surfaceMuted : KajiTheme.tertiaryBackground)
                KajiIcon(systemName: "plus", size: 12)
                    .foregroundStyle(hovered ? KajiTheme.fg : KajiTheme.fgMuted)
            }
            .frame(width: 28, height: 28)

            Text("Add Project")
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(hovered ? KajiTheme.fg : KajiTheme.fgMuted)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(hovered ? KajiTheme.hover : Color.clear, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
    }
}

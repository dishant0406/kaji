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
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .fill(hovered ? DroidTheme.hover : Color.clear)
            DroidIcon(systemName: "plus", size: 14)
                .foregroundStyle(hovered ? DroidTheme.fg : DroidTheme.fgMuted)
        }
        .frame(width: 36, height: 36)
    }

    private var expandedLayout: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: DroidShape.controlRadius)
                    .fill(hovered ? DroidTheme.surfaceMuted : DroidTheme.tertiaryBackground)
                DroidIcon(systemName: "plus", size: 12)
                    .foregroundStyle(hovered ? DroidTheme.fg : DroidTheme.fgMuted)
            }
            .frame(width: 28, height: 28)

            Text("Add Project")
                .droidFont(size: 12, weight: .medium)
                .foregroundStyle(hovered ? DroidTheme.fg : DroidTheme.fgMuted)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(hovered ? DroidTheme.hover : Color.clear, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
    }
}

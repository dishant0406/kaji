import SwiftUI

struct UpdateBadge: View {
    let version: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                DroidIcon(systemName: "arrow.down.circle.fill", size: 9)
                Text("Update \(version)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundStyle(hovered ? DroidTheme.accent : DroidTheme.fgMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: DroidShape.badgeRadius)
                    .fill(DroidTheme.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.badgeRadius)
                    .stroke(DroidTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Update available: version \(version)")
        .accessibilityHint("Activates to check for updates")
    }
}

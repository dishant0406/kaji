import SwiftUI

struct FileTreeIconButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .fill(hovered ? DroidTheme.surface : .clear)
                DroidIcon(systemName: "sidebar.left", size: 13)
                    .foregroundStyle(hovered ? DroidTheme.fg : DroidTheme.fgMuted)
            }
            .frame(width: 28, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .strokeBorder(hovered ? DroidTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("File Tree")
    }
}

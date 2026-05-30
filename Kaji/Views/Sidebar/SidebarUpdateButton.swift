import SwiftUI

struct SidebarUpdateButton: View {
    let version: String
    var isChecking = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isChecking {
                    KajiSpinner(size: 13, lineWidth: 1.5)
                } else {
                    KajiIcon(systemName: "arrow.down.circle.fill", size: 13)
                }
            }
            .foregroundStyle(hovered ? KajiTheme.accent : KajiTheme.fgMuted)
            .frame(width: 28, height: 28)
            .background(background, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .strokeBorder(hovered ? KajiTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .disabled(isChecking)
        .onHover { hovered = $0 }
        .kajiChangeFeedback(KajiMotion.successFeedback, value: version)
        .help("Update available: \(version)")
        .accessibilityLabel("Update available")
        .accessibilityValue(version)
    }

    private var background: Color {
        hovered ? KajiTheme.surface : .clear
    }
}

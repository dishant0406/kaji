import SwiftUI

struct AgentInstructionTab: View {
    let group: AgentInstructionGroup
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                KajiIcon(systemName: group.iconName, size: 11)
                Text(group.displayName)
                    .kajiFont(size: 12, weight: .medium)
                Text("\(group.documents.count)")
                    .kajiFont(size: 10, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgDim)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(KajiTheme.bg, in: Capsule())
            }
            .foregroundStyle(selected || hovered ? KajiTheme.fg : KajiTheme.fgMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected || hovered ? KajiTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected ? KajiTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .kajiPointer()
    }
}

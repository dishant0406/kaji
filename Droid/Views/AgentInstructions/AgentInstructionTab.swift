import SwiftUI

struct AgentInstructionTab: View {
    let group: AgentInstructionGroup
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                DroidIcon(systemName: group.iconName, size: 11)
                Text(group.displayName)
                    .droidFont(size: 12, weight: .medium)
                Text("\(group.documents.count)")
                    .droidFont(size: 10, weight: .semibold)
                    .foregroundStyle(DroidTheme.fgDim)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DroidTheme.bg, in: Capsule())
            }
            .foregroundStyle(selected || hovered ? DroidTheme.fg : DroidTheme.fgMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected || hovered ? DroidTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected ? DroidTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .droidPointer()
    }
}

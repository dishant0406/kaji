import SwiftUI

struct AgentCommandCenterRow: View {
    let entry: AgentCommandCenterEntry
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            DroidIcon(systemName: iconName, size: 12)
                .foregroundStyle(isHighlighted ? DroidTheme.fg : DroidTheme.fgMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.title)
                        .droidFont(size: 13, weight: .medium)
                        .foregroundStyle(DroidTheme.fg)
                        .lineLimit(1)
                    Text(entry.category)
                        .droidFont(size: 11)
                        .foregroundStyle(isHighlighted ? DroidTheme.fgMuted : DroidTheme.fgDim)
                        .lineLimit(1)
                }
                Text(entry.detail)
                    .droidFont(size: 11)
                    .foregroundStyle(isHighlighted ? DroidTheme.fgMuted : DroidTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(entry.shortcut)
                .droidFont(size: 11, design: .monospaced)
                .foregroundStyle(isHighlighted ? DroidTheme.fgMuted : DroidTheme.fgDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DroidShape.panelRadius)
                .fill(isHighlighted ? DroidTheme.secondaryBackground : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.panelRadius)
                .stroke(isHighlighted ? DroidTheme.borderStrong : .clear, lineWidth: 1)
        )
    }

    private var iconName: String {
        switch entry.action {
        case .jump:
            "arrow.turn.down.right"
        case .reply:
            "arrowshape.turn.up.left"
        case .stop:
            "escape"
        case .newRun:
            "plus"
        case .resume:
            "play"
        case .verify:
            "checkmark.circle"
        case .openFile:
            "doc.text"
        case .openDiff:
            "square.split.2x1"
        }
    }
}

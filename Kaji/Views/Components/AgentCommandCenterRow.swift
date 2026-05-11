import SwiftUI

struct AgentCommandCenterRow: View {
    let entry: AgentCommandCenterEntry
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: iconName, size: 12)
                .foregroundStyle(isHighlighted ? KajiTheme.fg : KajiTheme.fgMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.title)
                        .kajiFont(size: 13, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                        .lineLimit(1)
                    Text(entry.category)
                        .kajiFont(size: 11)
                        .foregroundStyle(isHighlighted ? KajiTheme.fgMuted : KajiTheme.fgDim)
                        .lineLimit(1)
                }
                Text(entry.detail)
                    .kajiFont(size: 11)
                    .foregroundStyle(isHighlighted ? KajiTheme.fgMuted : KajiTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(entry.shortcut)
                .kajiFont(size: 11, design: .monospaced)
                .foregroundStyle(isHighlighted ? KajiTheme.fgMuted : KajiTheme.fgDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .fill(isHighlighted ? KajiTheme.secondaryBackground : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .stroke(isHighlighted ? KajiTheme.borderStrong : .clear, lineWidth: 1)
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

import SwiftUI

struct KajiAgentToolGroupHeaderView: View {
    let group: KajiAgentToolGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    var onInspect: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KajiIcon(systemName: group.hasError ? "xmark" : "wrench.and.screwdriver", size: 12)
                .foregroundStyle(group.hasError ? KajiTheme.diffRemoveFg : KajiTheme.fgMuted)
                .frame(width: 18, height: 20)
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    KajiIcon(systemName: isExpanded ? "chevron.down" : "chevron.right", size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                    Text(group.title)
                        .kajiFont(size: 12, weight: .semibold)
                        .foregroundStyle(group.hasError ? KajiTheme.diffRemoveFg : KajiTheme.fg)
                    Text("\(group.tools.count)")
                        .kajiFont(size: 11, design: .monospaced)
                        .foregroundStyle(KajiTheme.fgDim)
                    if !group.isComplete {
                        KajiSpinner(size: 10)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onInspect {
                Button(action: onInspect) {
                    Text("Details")
                        .kajiFont(size: 11.5, weight: .medium)
                        .foregroundStyle(KajiTheme.fgDim)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .kajiPointer()
            }
        }
        .padding(.vertical, 8)
    }
}

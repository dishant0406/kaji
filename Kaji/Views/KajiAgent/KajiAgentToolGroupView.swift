import SwiftUI

struct KajiAgentToolGroupView: View {
    let group: KajiAgentToolGroup
    @Binding var expandedGroups: Set<UUID>
    @Binding var collapsedGroups: Set<UUID>

    private var expanded: Bool { expandedGroups.contains(group.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KajiIcon(systemName: group.hasError ? "xmark" : "wrench.and.screwdriver", size: 12)
                .foregroundStyle(group.hasError ? KajiTheme.diffRemoveFg : KajiTheme.fgMuted)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: 8) {
                Button { toggleExpanded() } label: {
                    HStack(spacing: 8) {
                        KajiIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 10)
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
                }
                .buttonStyle(.plain)
                .kajiPointer()

                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(group.tools) { tool in
                            KajiAgentMessageRow(message: tool)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    private func toggleExpanded() {
        if expanded {
            expandedGroups.remove(group.id)
            collapsedGroups.insert(group.id)
        } else {
            collapsedGroups.remove(group.id)
            expandedGroups.insert(group.id)
        }
    }
}

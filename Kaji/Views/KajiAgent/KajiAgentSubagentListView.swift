import SwiftUI

struct KajiAgentSubagentListView: View {
    let layout: KajiAgentSubagentInlineLayout
    @Environment(KajiModalCoordinator.self) private var modalCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(alignment: .leading, spacing: 4) {
                ForEach(layout.inlineAgents) { agent in
                    KajiAgentSubagentRow(agent: agent) {
                        modalCoordinator.present(.subagent(agent))
                    }
                }
                if layout.hasOverflow {
                    overflowRow
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Subagents")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text(layout.summary)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgDim)
            Spacer(minLength: 0)
        }
    }

    private var overflowRow: some View {
        Button {
            modalCoordinator.present(.subagents(layout.agents))
        } label: {
            HStack(spacing: 8) {
                KajiIcon(systemName: "ellipsis.circle", size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(width: 14, height: 16)
                Text("\(layout.overflowCount) more subagent\(layout.overflowCount == 1 ? "" : "s")")
                    .kajiFont(size: 11, weight: .medium)
                    .foregroundStyle(KajiTheme.fgMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KajiTheme.bg.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(KajiTheme.border.opacity(0.42)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .kajiPointer()
    }
}

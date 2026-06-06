import SwiftUI

struct KajiAgentTaskToolView: View {
    let details: KajiAgentTaskToolDetails
    @Environment(KajiModalCoordinator.self) private var modalCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Subagents")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text(summary)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(details.visibleAgents) { agent in
                    Button { modalCoordinator.present(.subagent(agent)) } label: {
                        KajiAgentSubagentRow(agent: agent)
                    }
                    .buttonStyle(.plain)
                    .kajiPointer()
                }
            }
        }
    }

    private var summary: String {
        let agents = details.visibleAgents
        let running = agents.count(where: { $0.status == "running" || $0.status == "pending" })
        let completed = agents.count(where: { $0.status == "completed" })
        let failed = agents.count(where: { $0.status == "failed" || $0.status == "aborted" })
        return "\(running) running · \(completed) done · \(failed) failed"
    }
}

private struct KajiAgentSubagentRow: View {
    let agent: KajiAgentSubagentProgress

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KajiIcon(systemName: icon, size: 11)
                .foregroundStyle(color)
                .frame(width: 14, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.description?.nilIfEmpty ?? agent.id)
                        .kajiFont(size: 11, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                        .lineLimit(1)
                    Text(agent.agent)
                        .kajiFont(size: 10, design: .monospaced)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                }
                Text(detail)
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(KajiTheme.bg.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var detail: String {
        if let currentTool = agent.currentTool, !currentTool.isEmpty {
            return "\(agent.status) · \(currentTool) · \(agent.toolCount) tools · \(agent.tokens) tokens"
        }
        return "\(agent.status) · \(agent.toolCount) tools · \(agent.tokens) tokens"
    }

    private var icon: String {
        switch agent.status {
        case "completed": "checkmark.circle.fill"
        case "failed",
             "aborted": "xmark.circle.fill"
        default: "circle.dotted"
        }
    }

    private var color: Color {
        switch agent.status {
        case "completed": KajiTheme.diffAddFg
        case "failed",
             "aborted": KajiTheme.diffRemoveFg
        default: KajiTheme.fgMuted
        }
    }
}

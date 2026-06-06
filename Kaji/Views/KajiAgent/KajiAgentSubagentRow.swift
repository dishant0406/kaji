import SwiftUI

struct KajiAgentSubagentRow: View {
    let agent: KajiAgentSubagentProgress
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 8) {
                KajiIcon(systemName: icon, size: 11)
                    .foregroundStyle(color)
                    .frame(width: 14, height: 17)
                VStack(alignment: .leading, spacing: 2) {
                    title
                    Text(detail)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(KajiTheme.bg.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .kajiPointer()
    }

    private var title: some View {
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

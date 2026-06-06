import SwiftUI

struct KajiAgentSubagentDetailView: View {
    let agent: KajiAgentSubagentProgress
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(agent.description?.nilIfEmpty ?? agent.id)
                    .kajiFont(size: 14, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    KajiIcon(systemName: "xmark", size: 11)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .kajiPointer()
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(agent.assignment ?? agent.task)
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        info("Agent", agent.agent)
                        info("Status", agent.status)
                        info("Current tool", agent.currentTool ?? "-")
                        info("Tokens", String(agent.tokens))
                        info("Duration", "\(agent.durationMs / 1000)s")
                        if let sessionFile = agent.sessionFile { info("Transcript", sessionFile) }
                    }
                    if let failureText = agent.failureText?.nilIfEmpty {
                        Text("Failure")
                            .kajiFont(size: 12, weight: .semibold)
                            .foregroundStyle(KajiTheme.fg)
                        Text(failureText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(KajiTheme.diffRemoveFg)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !agent.recentOutput.isEmpty {
                        Text("Recent output")
                            .kajiFont(size: 12, weight: .semibold)
                            .foregroundStyle(KajiTheme.fg)
                        Text(agent.recentOutput.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(KajiTheme.fgDim)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 640, height: 520, alignment: .topLeading)
        .background(KajiTheme.bg, in: RoundedRectangle(cornerRadius: 12))
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .textSelection(.enabled)
        }
    }
}

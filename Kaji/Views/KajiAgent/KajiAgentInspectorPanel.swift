import SwiftUI

struct KajiAgentInspectorPanel: View {
    let item: KajiAgentInspectorItem
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(KajiTheme.border)
            ScrollView(.vertical, showsIndicators: true) {
                content
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 360, idealWidth: 440, maxWidth: 520, maxHeight: .infinity)
        .background(KajiTheme.secondaryBackground.opacity(0.48))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text(item.subtitle)
                    .kajiFont(size: 11.5)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                KajiIcon(systemName: "xmark", size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .help("Close inspector")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case let .thinking(message):
            thinkingContent(message)
        case let .tool(message):
            toolContent(message)
        case let .toolGroup(group):
            toolGroupContent(group)
        }
    }

    private func thinkingContent(_ message: KajiAgentMessage) -> some View {
        KajiAgentMarkdownText(
            content: message.detail.nilIfEmpty ?? "No reasoning content recorded.",
            size: 13,
            color: KajiTheme.fgMuted
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolContent(_ message: KajiAgentMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            toolMetadata(message)
            if let output = message.kajiAgentToolOutput {
                KajiAgentToolOutputView(output: output, toolName: message.title)
            } else if let details = message.taskDetails {
                KajiAgentTaskToolView(details: details)
            } else {
                KajiAgentEmptyInspectorMessage(text: "No output was captured for this tool call.")
            }
            if let details = message.taskDetails, message.kajiAgentToolOutput != nil {
                KajiAgentTaskToolView(details: details)
            }
        }
    }

    private func toolMetadata(_ message: KajiAgentMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let arguments = message.toolArguments, !arguments.isEmpty {
                inspectorField(title: "Arguments", value: arguments.replacingOccurrences(of: "\n", with: "  "))
            }
            inspectorField(title: "Status", value: item.subtitle)
        }
    }

    private func toolGroupContent(_ group: KajiAgentToolGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(group.tools) { tool in
                HStack(spacing: 8) {
                    KajiIcon(systemName: tool.isError ? "xmark" : tool.isComplete ? "checkmark" : "circle.dotted", size: 10)
                        .foregroundStyle(tool.isError ? KajiTheme.diffRemoveFg : KajiTheme.fgMuted)
                        .frame(width: 14)
                    Text(tool.title)
                        .kajiFont(size: 12, weight: .medium)
                        .foregroundStyle(tool.isError ? KajiTheme.diffRemoveFg : KajiTheme.fg)
                    Text(tool.kajiAgentToolOutput == nil ? "No output" : "Output")
                        .kajiFont(size: 11.5)
                        .foregroundStyle(KajiTheme.fgDim)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func inspectorField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
            Text(value)
                .kajiFont(size: 12, design: .monospaced)
                .foregroundStyle(KajiTheme.fgMuted)
                .textSelection(.enabled)
        }
    }
}

private struct KajiAgentEmptyInspectorMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .kajiFont(size: 12.5)
            .foregroundStyle(KajiTheme.fgMuted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KajiTheme.bg.opacity(0.56), in: RoundedRectangle(cornerRadius: KajiAgentTranscriptMetrics.controlRadius))
    }
}

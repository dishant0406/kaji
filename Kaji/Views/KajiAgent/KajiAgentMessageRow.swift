import SwiftUI

struct KajiAgentMessageRow: View, Equatable {
    let message: KajiAgentMessage
    var toolExpanded: Bool?
    var onToggleToolExpanded: (() -> Void)?
    var onInspectTool: (() -> Void)?
    @State private var localToolExpanded = false

    nonisolated static func == (lhs: KajiAgentMessageRow, rhs: KajiAgentMessageRow) -> Bool {
        lhs.message == rhs.message && lhs.toolExpanded == rhs.toolExpanded
    }

    var body: some View {
        switch message.kind {
        case .user:
            userRow
                .padding(.top, 18)
                .padding(.bottom, 10)
        case .assistant:
            iconRow(icon: "sparkles", color: KajiTheme.fgMuted) {
                if message.isComplete {
                    KajiAgentLongTextView(
                        content: message.detail,
                        size: KajiAgentTranscriptMetrics.assistantFont,
                        color: KajiTheme.fg
                    )
                    .frame(maxWidth: KajiAgentTranscriptMetrics.proseWidth, alignment: .leading)
                } else {
                    KajiAgentStreamingMarkdownText(
                        content: message.detail,
                        size: KajiAgentTranscriptMetrics.assistantFont,
                        color: KajiTheme.fg
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: KajiAgentTranscriptMetrics.proseWidth, alignment: .leading)
                }
            }
            .padding(.top, 5)
            .padding(.bottom, 18)
        case .thinking:
            KajiAgentThinkingRow(message: message, isExpanded: false, onToggle: {})
        case .tool:
            KajiAgentToolCallRow(
                message: message,
                isExpanded: isToolExpanded,
                onToggle: toggleToolExpanded,
                onInspect: onInspectTool
            )
        case .event:
            systemRow(color: KajiTheme.fgMuted)
                .padding(.vertical, 8)
        case .error:
            systemRow(color: KajiTheme.diffRemoveFg)
                .padding(.vertical, 8)
        }
    }

    private var userRow: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 90)
            KajiAgentLongTextView(content: message.detail, size: KajiAgentTranscriptMetrics.userFont, color: KajiTheme.fg)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiAgentTranscriptMetrics.messageRadius))
                .overlay(RoundedRectangle(cornerRadius: KajiAgentTranscriptMetrics.messageRadius).stroke(KajiTheme.border.opacity(0.55)))
                .frame(maxWidth: KajiAgentTranscriptMetrics.userWidth, alignment: .trailing)
        }
    }

    private var isToolExpanded: Bool {
        toolExpanded ?? localToolExpanded
    }

    private func toggleToolExpanded() {
        if let onToggleToolExpanded {
            onToggleToolExpanded()
            return
        }
        localToolExpanded.toggle()
    }

    private func systemRow(color: Color) -> some View {
        iconRow(icon: message.kind == .error ? "xmark" : "sparkles", color: color) {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(color)
                if !message.detail.isEmpty {
                    KajiAgentLongTextView(content: message.detail, size: KajiAgentTranscriptMetrics.systemFont, color: KajiTheme.fgMuted)
                }
            }
        }
    }

    private func iconRow(icon: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 14) {
            KajiIcon(systemName: icon, size: 12)
                .foregroundStyle(color)
                .frame(width: 18, height: 20)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

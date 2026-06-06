import SwiftUI

struct KajiAgentMessageRow: View {
    let message: KajiAgentMessage
    @State private var expanded = false

    var body: some View {
        switch message.kind {
        case .user:
            userRow
                .padding(.top, 18)
                .padding(.bottom, 10)
        case .assistant:
            iconRow(icon: "sparkles", color: KajiTheme.fgMuted) {
                if message.isComplete {
                    ParentAgentMarkdownText(content: message.detail, color: KajiTheme.fgMuted)
                } else {
                    KajiAgentStreamingMarkdownText(content: message.detail, color: KajiTheme.fgMuted)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 20)
        case .thinking:
            systemRow(color: KajiTheme.fgMuted)
                .padding(.vertical, 8)
        case .tool:
            toolRow
                .padding(.vertical, 8)
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
            ParentAgentMarkdownText(content: message.detail, color: KajiTheme.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 520, alignment: .trailing)
        }
    }

    private var toolRow: some View {
        iconRow(
            icon: message.isError ? "xmark" : "wrench.and.screwdriver",
            color: message.isError ? KajiTheme.diffRemoveFg : KajiTheme.fgMuted
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(message.title)
                        .kajiFont(size: 12, weight: .semibold)
                        .foregroundStyle(message.isError ? KajiTheme.diffRemoveFg : KajiTheme.fg)
                    if let args = message.toolArguments, !args.isEmpty {
                        Text(args.replacingOccurrences(of: "\n", with: "  "))
                            .kajiFont(size: 11, design: .monospaced)
                            .foregroundStyle(KajiTheme.fgDim)
                            .lineLimit(1)
                    }
                    if !message.isComplete {
                        KajiSpinner(size: 10)
                    }
                }
                if !message.detail.isEmpty {
                    toolOutput
                }
                if let taskDetails = message.taskDetails {
                    KajiAgentTaskToolView(details: taskDetails)
                }
            }
        }
    }

    private var toolOutput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    KajiIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                    Text(message.detail)
                        .kajiFont(size: 11, weight: .medium)
                        .foregroundStyle(KajiTheme.fgMuted)
                    if message.truncatedLineCount > 0, !expanded {
                        Text("\(message.truncatedLineCount) more")
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.fgDim)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .kajiPointer()

            if let preview = expanded ? message.fullOutput : message.preview, !preview.isEmpty {
                ScrollView(.vertical, showsIndicators: expanded) {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(KajiTheme.fgDim)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: expanded ? 360 : 180)
                .padding(10)
                .background(KajiTheme.bg.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(KajiTheme.border.opacity(0.55)))
            }
        }
    }

    private func systemRow(color: Color) -> some View {
        iconRow(icon: message.kind == .error ? "xmark" : "sparkles", color: color) {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(color)
                if !message.detail.isEmpty {
                    ParentAgentMarkdownText(content: message.detail, size: 12, color: KajiTheme.fgDim)
                }
            }
        }
    }

    private func iconRow(icon: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            KajiIcon(systemName: icon, size: 12)
                .foregroundStyle(color)
                .frame(width: 18, height: 20)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

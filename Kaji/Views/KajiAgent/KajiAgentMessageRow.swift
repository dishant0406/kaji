import SwiftUI

struct KajiAgentMessageRow: View, Equatable {
    let message: KajiAgentMessage
    var toolExpanded: Bool?
    var onToggleToolExpanded: (() -> Void)?
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
                    KajiAgentLongTextView(content: message.detail, color: KajiTheme.fgMuted)
                } else {
                    KajiAgentStreamingMarkdownText(content: message.detail, color: KajiTheme.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
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
            KajiAgentLongTextView(content: message.detail, color: KajiTheme.fg)
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
                if hasToolDetails {
                    toolDisclosure
                }
                if isToolExpanded {
                    expandedToolDetails
                }
            }
        }
    }

    private var toolDisclosure: some View {
        Button {
            toggleToolExpanded()
        } label: {
            HStack(spacing: 8) {
                KajiIcon(systemName: isToolExpanded ? "chevron.down" : "chevron.right", size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
                Text(toolStatusText)
                    .kajiFont(size: 11, weight: .medium)
                    .foregroundStyle(message.isError ? KajiTheme.diffRemoveFg : KajiTheme.fgMuted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kajiPointer()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandedToolDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = expandedOutput, !preview.isEmpty {
                ScrollView(.vertical, showsIndicators: isToolExpanded) {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(KajiTheme.fgDim)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
                .padding(10)
                .background(KajiTheme.bg.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(KajiTheme.border.opacity(0.55)))
            }
            if let taskDetails = message.taskDetails {
                KajiAgentTaskToolView(details: taskDetails)
            }
        }
    }

    private var hasToolDetails: Bool {
        expandedOutput != nil || message.taskDetails != nil
    }

    private var expandedOutput: String? {
        if let fullOutput = message.fullOutput, !fullOutput.isEmpty { return fullOutput }
        if let preview = message.preview, !preview.isEmpty { return preview }
        return nil
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

    private var toolStatusText: String {
        if message.isError { return "Failed" }
        if !message.isComplete { return expandedOutput == nil ? "Running" : "Streaming result" }
        return expandedOutput == nil && message.taskDetails == nil ? "No output" : "Result ready"
    }

    private func systemRow(color: Color) -> some View {
        iconRow(icon: message.kind == .error ? "xmark" : "sparkles", color: color) {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(color)
                if !message.detail.isEmpty {
                    KajiAgentLongTextView(content: message.detail, size: 12, color: KajiTheme.fgDim)
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

import SwiftUI

struct KajiAgentToolCallRow: View, Equatable {
    let message: KajiAgentMessage
    var isExpanded: Bool
    let onToggle: () -> Void
    var onInspect: (() -> Void)?

    nonisolated static func == (lhs: KajiAgentToolCallRow, rhs: KajiAgentToolCallRow) -> Bool {
        lhs.message == rhs.message && lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        KajiAccordionItem(
            isExpanded: isExpanded && hasDetails,
            isEnabled: hasDetails,
            accessibilityLabel: message.title,
            style: .transcriptTool,
            onToggle: onToggle,
            header: { expanded in
                header(expanded: expanded)
            },
            content: {
                details
            }
        )
    }

    private func header(expanded: Bool) -> some View {
        let descriptor = KajiAgentToolRenderer.descriptor(for: message)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if hasDetails {
                    KajiIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 9)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(width: 10)
                }
                KajiIcon(systemName: descriptor.iconName, size: 11)
                    .foregroundStyle(message.isError ? KajiTheme.diffRemoveFg : KajiTheme.fgMuted)
                    .frame(width: 14)
                Text(descriptor.title)
                    .kajiFont(size: KajiAgentTranscriptMetrics.toolFont, weight: .semibold)
                    .foregroundStyle(message.isError ? KajiTheme.diffRemoveFg : KajiTheme.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(descriptor.subtitle)
                    .kajiFont(size: KajiAgentTranscriptMetrics.toolDetailFont, weight: .medium)
                    .foregroundStyle(message.isError ? KajiTheme.diffRemoveFg : KajiTheme.fgDim)
                if !message.isComplete { KajiSpinner(size: 9) }
                Spacer(minLength: 0)
            }
            if let args = descriptor.argumentPreview {
                Text(args)
                    .kajiFont(size: KajiAgentTranscriptMetrics.toolDetailFont, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(2)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let output, !output.isEmpty {
                if let onInspect {
                    KajiAgentToolOutputPreviewView(output: output, toolName: message.title, onOpen: onInspect)
                } else {
                    KajiAgentToolOutputView(output: output, toolName: message.title)
                }
            }
            if let taskDetails = message.taskDetails {
                KajiAgentTaskToolView(details: taskDetails)
            }
        }
    }

    private var hasDetails: Bool {
        output != nil || message.taskDetails != nil
    }

    private var output: String? {
        if let fullOutput = message.fullOutput, !fullOutput.isEmpty { return fullOutput }
        if let preview = message.preview, !preview.isEmpty { return preview }
        return nil
    }
}

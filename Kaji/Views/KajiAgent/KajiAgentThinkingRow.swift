import SwiftUI

struct KajiAgentThinkingRow: View, Equatable {
    let message: KajiAgentMessage
    let isExpanded: Bool
    let onToggle: () -> Void
    var onInspect: (() -> Void)?

    nonisolated static func == (lhs: KajiAgentThinkingRow, rhs: KajiAgentThinkingRow) -> Bool {
        lhs.message == rhs.message && lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        KajiAccordionItem(
            isExpanded: shouldShowDetail,
            isEnabled: canToggle,
            accessibilityLabel: message.isComplete ? "Thinking" : "Thinking in progress",
            style: .transcriptThinking,
            onToggle: toggle,
            header: { expanded in
                HStack(spacing: 8) {
                    if message.isComplete {
                        KajiIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 9)
                            .foregroundStyle(KajiTheme.fgDim)
                    } else {
                        KajiSpinner(size: 9)
                    }
                    Text(message.isComplete ? "Thinking" : "Thinking...")
                        .kajiFont(size: KajiAgentTranscriptMetrics.metadataFont, weight: .semibold)
                        .foregroundStyle(KajiTheme.fgMuted)
                    Spacer(minLength: 0)
                }
            },
            content: {
                if !message.detail.isEmpty {
                    KajiAgentLongTextView(
                        content: message.detail,
                        size: KajiAgentTranscriptMetrics.thinkingFont,
                        color: KajiTheme.fgMuted,
                        threshold: KajiAgentTranscriptMetrics.thinkingPreviewCharacters
                    )
                    .frame(maxWidth: KajiAgentTranscriptMetrics.proseWidth, alignment: .leading)
                    if let onInspect {
                        Button("Open reasoning details", action: onInspect)
                            .buttonStyle(.plain)
                            .kajiFont(size: 11.5, weight: .medium)
                            .foregroundStyle(KajiTheme.fgMuted)
                            .kajiPointer()
                    }
                }
            }
        )
    }

    private var shouldShowDetail: Bool {
        !message.detail.isEmpty && (isExpanded || !message.isComplete)
    }

    private var canToggle: Bool {
        message.isComplete && !message.detail.isEmpty
    }

    private func toggle() {
        onToggle()
    }
}

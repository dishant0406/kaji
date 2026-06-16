import SwiftUI

struct KajiAgentPlanSummaryRow: View, Equatable {
    let plan: KajiAgentPlanSummary
    let isExpanded: Bool
    let onToggle: () -> Void
    let onInspect: () -> Void

    nonisolated static func == (lhs: KajiAgentPlanSummaryRow, rhs: KajiAgentPlanSummaryRow) -> Bool {
        lhs.plan == rhs.plan && lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        KajiAccordionItem(
            isExpanded: isExpanded,
            accessibilityLabel: plan.message.isComplete ? "Plan" : "Planning",
            style: .transcriptThinking,
            onToggle: onToggle,
            header: { expanded in
                HStack(spacing: 8) {
                    KajiIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 9)
                        .foregroundStyle(KajiTheme.fgDim)
                    Text(plan.message.isComplete ? "Plan" : "Planning")
                        .kajiFont(size: KajiAgentTranscriptMetrics.metadataFont, weight: .semibold)
                        .foregroundStyle(KajiTheme.fgMuted)
                    Text(plan.summary)
                        .kajiFont(size: KajiAgentTranscriptMetrics.metadataFont)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                    if !plan.message.isComplete { KajiSpinner(size: 9) }
                    Spacer(minLength: 0)
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    KajiAgentMarkdownText(content: plan.summary, size: KajiAgentTranscriptMetrics.thinkingFont, color: KajiTheme.fgMuted)
                    Button("Open reasoning details", action: onInspect)
                        .buttonStyle(.plain)
                        .kajiFont(size: 11.5, weight: .medium)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .kajiPointer()
                }
            }
        )
    }
}

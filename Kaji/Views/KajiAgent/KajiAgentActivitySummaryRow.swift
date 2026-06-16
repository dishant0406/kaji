import SwiftUI

struct KajiAgentActivitySummaryRow: View, Equatable {
    let activity: KajiAgentActivitySummary
    let isExpanded: Bool
    let onToggle: () -> Void
    let onInspect: (KajiAgentInspectorItem) -> Void

    nonisolated static func == (lhs: KajiAgentActivitySummaryRow, rhs: KajiAgentActivitySummaryRow) -> Bool {
        lhs.activity == rhs.activity && lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        KajiAccordionItem(
            isExpanded: isExpanded,
            accessibilityLabel: activity.title,
            style: .transcriptTool,
            onToggle: onToggle,
            header: { expanded in
                HStack(spacing: 8) {
                    KajiIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 9)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(width: 10)
                    Text(activity.title)
                        .kajiFont(size: KajiAgentTranscriptMetrics.toolFont, weight: .semibold)
                        .foregroundStyle(activity.group.hasError ? KajiTheme.diffRemoveFg : KajiTheme.fg)
                    Text(activity.summary)
                        .kajiFont(size: KajiAgentTranscriptMetrics.toolDetailFont)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                    if !activity.group.isComplete { KajiSpinner(size: 9) }
                    Spacer(minLength: 0)
                    Text("Details")
                        .kajiFont(size: 11.5, weight: .medium)
                        .foregroundStyle(KajiTheme.fgDim)
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Open activity details") { onInspect(.toolGroup(activity.group)) }
                        .buttonStyle(.plain)
                        .kajiFont(size: 11.5, weight: .medium)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .kajiPointer()
                    ForEach(activity.actions) { action in
                        KajiAgentActivityActionRow(action: action) {
                            onInspect(.tool(action.message))
                        }
                    }
                }
            }
        )
    }
}

private struct KajiAgentActivityActionRow: View {
    let action: KajiAgentActivityAction
    let onInspect: () -> Void

    var body: some View {
        Button(action: onInspect) {
            HStack(alignment: .top, spacing: 8) {
                KajiIcon(systemName: icon, size: 10)
                    .foregroundStyle(action.isError ? KajiTheme.diffRemoveFg : KajiTheme.fgDim)
                    .frame(width: 14, height: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .kajiFont(size: 12.5, weight: .medium)
                        .foregroundStyle(action.isError ? KajiTheme.diffRemoveFg : KajiTheme.fgMuted)
                    Text(action.detail)
                        .kajiFont(size: 11.5, design: .monospaced)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kajiPointer()
    }

    private var icon: String {
        if action.isError { return "xmark" }
        if !action.isComplete { return "circle.dotted" }
        return "checkmark"
    }
}

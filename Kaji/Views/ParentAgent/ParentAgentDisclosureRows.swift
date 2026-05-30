import SwiftUI

struct ParentAgentThinkingRow: View {
    let item: ParentAgentTimelineItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureButton(
                title: item.isComplete ? "Thinking" : "Thinking...",
                count: nil,
                isExpanded: isExpanded,
                action: onToggle
            )
            if isExpanded, !item.detail.isEmpty {
                ParentAgentMarkdownText(content: item.detail, size: 12, color: KajiTheme.fgDim)
                    .padding(.leading, 22)
                    .transition(KajiMotion.disclosureTransition(reduceMotion: false))
            }
        }
        .padding(.vertical, 8)
        .animation(KajiMotion.panel, value: isExpanded)
    }
}

struct ParentAgentToolGroup: View {
    let items: [ParentAgentTimelineItem]
    let isActive: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureButton(
                title: title,
                count: isActive ? nil : items.count,
                isExpanded: isExpanded,
                isBusy: isActive,
                action: onToggle
            )
            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(items) { item in
                        ParentAgentToolSummaryRow(item: item)
                    }
                }
                .padding(.leading, 22)
                .transition(KajiMotion.disclosureTransition(reduceMotion: false))
            }
        }
        .padding(.vertical, 8)
        .animation(KajiMotion.panel, value: isExpanded)
    }

    private var title: String {
        guard isActive, let item = items.last else { return "Tools" }
        if item.detail.isEmpty { return item.title }
        return "\(item.title): \(item.detail)"
    }
}

private struct ParentAgentToolSummaryRow: View {
    let item: ParentAgentTimelineItem

    var body: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: item.kind == .tool ? "terminal" : "sparkles", size: 10)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 14)
            Text(item.title)
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
private func disclosureButton(
    title: String,
    count: Int?,
    isExpanded: Bool,
    isBusy: Bool = false,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 8) {
            if isBusy {
                KajiSpinner(size: 10)
            } else {
                KajiIcon(systemName: isExpanded ? "chevron.down" : "chevron.right", size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Text(title)
                .kajiFont(size: 12, weight: .medium)
                .lineLimit(1)
            if let count {
                Text("\(count)")
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
            }
        }
        .foregroundStyle(KajiTheme.fgMuted)
    }
    .buttonStyle(.plain)
    .kajiChangeFeedback(KajiMotion.selectionFeedback, value: isExpanded)
}

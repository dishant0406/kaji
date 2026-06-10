import SwiftUI

struct ParentAgentThinkingRow: View {
    let item: ParentAgentTimelineItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        KajiAccordionItem(
            isExpanded: isExpanded && !item.detail.isEmpty,
            isEnabled: item.isComplete && !item.detail.isEmpty,
            accessibilityLabel: item.isComplete ? "Thinking" : "Thinking in progress",
            style: .parentAgent,
            onToggle: onToggle,
            header: { expanded in
                disclosureLabel(
                    title: item.isComplete ? "Thinking" : "Thinking...",
                    count: nil,
                    isExpanded: expanded,
                    isBusy: !item.isComplete
                )
            },
            content: {
                if !item.detail.isEmpty {
                    ParentAgentMarkdownText(content: item.detail, size: 12, color: KajiTheme.fgDim)
                }
            }
        )
    }
}

struct ParentAgentToolGroup: View {
    let items: [ParentAgentTimelineItem]
    let isActive: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        KajiAccordionItem(
            isExpanded: isExpanded,
            isEnabled: !items.isEmpty,
            accessibilityLabel: title,
            style: .parentAgent,
            onToggle: onToggle,
            header: { expanded in
                disclosureLabel(
                    title: title,
                    count: isActive ? nil : items.count,
                    isExpanded: expanded,
                    isBusy: isActive
                )
            },
            content: {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(items) { item in
                        ParentAgentToolSummaryRow(item: item)
                    }
                }
            }
        )
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
private func disclosureLabel(
    title: String,
    count: Int?,
    isExpanded: Bool,
    isBusy: Bool = false
) -> some View {
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

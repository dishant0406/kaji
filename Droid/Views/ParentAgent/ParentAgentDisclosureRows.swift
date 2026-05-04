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
                ParentAgentMarkdownText(content: item.detail, size: 12, color: DroidTheme.fgDim)
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 8)
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
            }
        }
        .padding(.vertical, 8)
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
            DroidIcon(systemName: item.kind == .tool ? "terminal" : "sparkles", size: 10)
                .foregroundStyle(DroidTheme.fgDim)
                .frame(width: 14)
            Text(item.title)
                .droidFont(size: 12, weight: .medium)
                .foregroundStyle(DroidTheme.fgMuted)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
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
                DroidSpinner(size: 10)
            } else {
                DroidIcon(systemName: isExpanded ? "chevron.down" : "chevron.right", size: 10)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            Text(title)
                .droidFont(size: 12, weight: .medium)
                .lineLimit(1)
            if let count {
                Text("\(count)")
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
            }
        }
        .foregroundStyle(DroidTheme.fgMuted)
    }
    .buttonStyle(.plain)
}

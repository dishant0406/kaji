import SwiftUI

struct ParentAgentThinkingRow: View {
    let item: ParentAgentTimelineItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureButton(title: item.isComplete ? "Thinking" : "Thinking...", count: nil, isExpanded: isExpanded, action: onToggle)
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
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureButton(title: "Tools", count: items.count, isExpanded: isExpanded, action: onToggle)
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
private func disclosureButton(title: String, count: Int?, isExpanded: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 8) {
            DroidIcon(systemName: isExpanded ? "chevron.down" : "chevron.right", size: 10)
                .foregroundStyle(DroidTheme.fgDim)
            Text(title)
                .droidFont(size: 12, weight: .medium)
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

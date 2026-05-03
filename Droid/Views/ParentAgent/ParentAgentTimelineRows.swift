import SwiftUI

struct ParentAgentHeaderControls: View {
    let onNewThread: () -> Void
    let showsNewThread: Bool

    var body: some View {
        HStack(spacing: 8) {
            DroidPill(
                title: providerLabel,
                leadingIcon: "sparkles",
                trailingIcon: "chevron.down",
                variant: .filled
            ) {
                NotificationCenter.default.post(name: .openParentAgentSettings, object: nil)
            }
            .help("Parent Agent settings")

            if showsNewThread {
                DroidPill(
                    title: "New thread",
                    leadingIcon: "plus",
                    variant: .plain,
                    action: onNewThread
                )
                .help("Start a new parent-agent thread")
            }
        }
    }

    private var providerLabel: String {
        let settings = ParentAgentSettingsStore.shared
        return "\(settings.provider.title) / \(settings.modelID)"
    }
}

struct ParentAgentTimelineRow: View {
    let item: ParentAgentTimelineItem

    var body: some View {
        switch item.kind {
        case .user:
            userRow
                .padding(.top, 18)
                .padding(.bottom, 10)
        case .assistant:
            assistantRow
                .padding(.top, 4)
                .padding(.bottom, 20)
        case .error:
            systemRow(color: DroidTheme.diffRemoveFg)
                .padding(.vertical, 10)
        case .event:
            systemRow(color: DroidTheme.fgMuted)
                .padding(.vertical, 10)
        case .final,
             .thinking,
             .tool:
            EmptyView()
        }
    }

    private var userRow: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 90)
            MarkdownInlineText(content: item.detail, color: DroidTheme.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 520, alignment: .trailing)
        }
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 12) {
            DroidIcon(systemName: "sparkles", size: 13)
                .foregroundStyle(DroidTheme.fgDim)
                .frame(width: 18, height: 20)
            MarkdownInlineText(content: item.detail, color: DroidTheme.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func systemRow(color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DroidIcon(systemName: item.kind == .error ? "xmark" : "sparkles", size: 12)
                .foregroundStyle(color)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .droidFont(size: 12, weight: .medium)
                    .foregroundStyle(color)
                if !item.detail.isEmpty {
                    MarkdownInlineText(content: item.detail, size: 12, color: DroidTheme.fgDim)
                }
            }
        }
    }
}

struct ParentAgentThinkingRow: View {
    let item: ParentAgentTimelineItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureButton(title: item.isComplete ? "Thinking" : "Thinking...", count: nil, isExpanded: isExpanded, action: onToggle)
            if isExpanded, !item.detail.isEmpty {
                MarkdownInlineText(content: item.detail, size: 12, color: DroidTheme.fgDim)
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
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 8)
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

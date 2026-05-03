import SwiftUI

struct ParentAgentTimelineView: View {
    let task: ParentAgentTask
    @State private var expandedToolGroupIDs: Set<UUID> = []
    @State private var expandedThinkingIDs: Set<UUID> = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(timelineBlocks) { block in
                        timelineBlock(block)
                            .id(block.id)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: task.timeline.count) {
                guard let last = task.timeline.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func timelineBlock(_ block: ParentAgentTimelineBlock) -> some View {
        switch block {
        case let .item(item):
            if item.kind == .thinking {
                ParentAgentThinkingRow(
                    item: item,
                    isExpanded: thinkingExpanded(item),
                    onToggle: { toggleThinking(item.id) }
                )
            } else {
                ParentAgentTimelineRow(item: item)
            }
        case let .tools(items):
            ParentAgentToolGroup(
                items: items,
                isExpanded: expandedToolGroupIDs.contains(items[0].id),
                onToggle: { toggleToolGroup(items[0].id) }
            )
        }
    }

    private var timelineBlocks: [ParentAgentTimelineBlock] {
        var blocks: [ParentAgentTimelineBlock] = []
        var tools: [ParentAgentTimelineItem] = []

        func flushTools() {
            guard !tools.isEmpty else { return }
            blocks.append(.tools(tools))
            tools = []
        }

        for item in task.timeline where item.kind != .final {
            if item.kind == .event, item.title == "Question", task.pendingQuestionToolID != nil {
                continue
            }
            if isToolLike(item) {
                tools.append(item)
                continue
            }
            flushTools()
            blocks.append(.item(item))
        }
        flushTools()
        return blocks
    }

    private func isToolLike(_ item: ParentAgentTimelineItem) -> Bool {
        if item.kind == .tool { return true }
        if item.kind == .event { return item.title != "Question" }
        return false
    }

    private func thinkingExpanded(_ item: ParentAgentTimelineItem) -> Bool {
        !item.isComplete || expandedThinkingIDs.contains(item.id)
    }

    private func toggleThinking(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedThinkingIDs.contains(id) {
                expandedThinkingIDs.remove(id)
            } else {
                expandedThinkingIDs.insert(id)
            }
        }
    }

    private func toggleToolGroup(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedToolGroupIDs.contains(id) {
                expandedToolGroupIDs.remove(id)
            } else {
                expandedToolGroupIDs.insert(id)
            }
        }
    }
}

enum ParentAgentTimelineBlock: Identifiable {
    case item(ParentAgentTimelineItem)
    case tools([ParentAgentTimelineItem])

    var id: UUID {
        switch self {
        case let .item(item): item.id
        case let .tools(items): items[0].id
        }
    }
}

import SwiftUI
struct ParentAgentTimelineRow: View {
    let item: ParentAgentTimelineItem
    @State private var runStore = AgentRunStore.shared
    @State private var feedStore = ChildAgentFeedStore.shared
    @State private var previewAttachment: AskAttachment?

    var body: some View {
        switch item.kind {
        case .user:
            userRow
                .padding(.top, 18)
                .padding(.bottom, 10)
                .overlay { attachmentPreview }
        case .assistant:
            assistantRow
                .padding(.top, 4)
                .padding(.bottom, 20)
        case .childRun:
            childRunRow
                .padding(.vertical, 10)
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
            VStack(alignment: .leading, spacing: 8) {
                if !item.detail.isEmpty {
                    ParentAgentMarkdownText(content: item.detail, color: DroidTheme.fg)
                }
                if !item.attachments.isEmpty {
                    ParentAgentTimelineAttachmentStrip(attachments: item.attachments) { previewAttachment = $0 }
                }
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 520, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let previewAttachment {
            AskAttachmentPreviewOverlay(attachment: previewAttachment) { self.previewAttachment = nil }
        }
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 12) {
            DroidIcon(systemName: "sparkles", size: 13)
                .foregroundStyle(DroidTheme.fgDim)
                .frame(width: 18, height: 20)
            if item.isComplete {
                ParentAgentMarkdownText(content: item.detail, color: DroidTheme.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(item.detail)
                    .droidFont(size: 13)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var childRunRow: some View {
        HStack(alignment: .top, spacing: 12) {
            DroidIcon(systemName: "terminal", size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(childRunTitle)
                    .droidFont(size: 12, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                Text(childRunDetail)
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
                if let recentEventText {
                    Text(recentEventText)
                        .droidFont(size: 12)
                        .foregroundStyle(DroidTheme.fgDim)
                        .lineLimit(3)
                }
            }
        }
    }

    private var liveRun: AgentRun? {
        guard let childRunID = item.childRunID else { return nil }
        return runStore.run(id: childRunID)
    }

    private var childRunTitle: String {
        liveRun.map { AgentMissionControlSnapshotBuilder.providerName(for: $0.providerID) } ?? item.title
    }

    private var childRunDetail: String {
        guard let liveRun else { return item.detail }
        return "\(liveRun.status.rawValue) · \(liveRun.title)"
    }

    private var recentEventText: String? {
        if let childRunID = item.childRunID,
           let text = feedStore.recentText(runID: childRunID, limit: 1).first
        {
            return text
        }
        guard let event = liveRun?.events.last else { return nil }
        return event.text
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
                    ParentAgentMarkdownText(content: item.detail, size: 12, color: DroidTheme.fgDim)
                }
            }
        }
    }
}

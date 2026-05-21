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
            systemRow(color: KajiTheme.diffRemoveFg)
                .padding(.vertical, 10)
        case .event:
            systemRow(color: KajiTheme.fgMuted)
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
                    ParentAgentMarkdownText(content: item.detail, color: KajiTheme.fg)
                }
                if !item.attachments.isEmpty {
                    ParentAgentTimelineAttachmentStrip(attachments: item.attachments) { previewAttachment = $0 }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
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
            KajiIcon(systemName: "sparkles", size: 13)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 18, height: 20)
            if item.isComplete {
                ParentAgentMarkdownText(content: item.detail, color: KajiTheme.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ParentAgentStreamingText(content: item.detail, color: KajiTheme.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var childRunRow: some View {
        HStack(alignment: .top, spacing: 12) {
            KajiIcon(systemName: "terminal", size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(childRunTitle)
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text(childRunDetail)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
                if let recentEventText {
                    Text(recentEventText)
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgDim)
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
            KajiIcon(systemName: item.kind == .error ? "xmark" : "sparkles", size: 12)
                .foregroundStyle(color)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(color)
                if !item.detail.isEmpty {
                    ParentAgentMarkdownText(content: item.detail, size: 12, color: KajiTheme.fgDim)
                }
            }
        }
    }
}

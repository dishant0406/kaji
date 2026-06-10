import SwiftUI

struct KajiAgentTimelineRowView: View {
    let row: KajiAgentTimelineRow
    let isToolGroupExpanded: (UUID) -> Bool
    let toggleToolGroup: (UUID) -> Void
    let isToolExpanded: (UUID) -> Bool
    let toggleTool: (UUID) -> Void
    let toggleThinking: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if row.startsTurn, let turnID = row.turnID {
                KajiAgentTurnAnchor(id: turnID)
                    .frame(height: 0)
                Color.clear.frame(height: KajiAgentTimelineRowSpacingPolicy.topSpacing(for: row))
            }
            if row.depth > 0 {
                nestedContent
            } else {
                content
            }
        }
        .id(row.id.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, KajiAgentTimelineRowSpacingPolicy.bottomSpacing(for: row))
    }

    private var nestedContent: some View {
        content
            .padding(.leading, nestedContentLeadingPadding)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(KajiTheme.borderStrong.opacity(0.48))
                    .frame(width: KajiAgentTranscriptMetrics.nestedRailWidth)
                    .padding(.leading, nestedRailLeadingPadding)
                    .padding(.vertical, 7)
            }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nestedRailLeadingPadding: CGFloat {
        CGFloat(row.depth) * KajiAgentTranscriptMetrics.nestedIndent
    }

    private var nestedContentLeadingPadding: CGFloat {
        nestedRailLeadingPadding + KajiAgentTranscriptMetrics.nestedRailWidth + 12
    }

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case let .widget(lines):
            KajiAgentWidgetLinesView(lines: lines)
                .padding(.bottom, 12)
        case let .queuedMessages(count):
            KajiAgentQueuedMessagesRow(count: count)
                .padding(.bottom, 12)
        case let .user(message),
              let .message(message):
            KajiAgentMessageRow(message: message)
                .equatable()
        case let .thinking(message, expanded):
            KajiAgentThinkingRow(
                message: message,
                isExpanded: expanded,
                onToggle: { toggleThinking(message.id) }
            )
            .equatable()
        case let .toolGroupHeader(group):
            KajiAgentToolGroupHeaderView(
                group: group,
                isExpanded: isToolGroupExpanded(group.id),
                onToggle: { toggleToolGroup(group.id) }
            )
        case let .tool(message, expanded):
            KajiAgentMessageRow(
                message: message,
                toolExpanded: expanded,
                onToggleToolExpanded: { toggleTool(message.id) }
            )
            .equatable()
        case let .latestTurnSpacer(height):
            Color.clear.frame(height: height)
        case .bottom:
            Color.clear.frame(height: 1).id(KajiAgentScrollTarget.bottom)
        }
    }
}

struct KajiAgentQueuedMessagesRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "tray.full", size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("\(count) queued message\(count == 1 ? "" : "s")")
                .kajiFont(size: KajiAgentTranscriptMetrics.metadataFont, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: KajiAgentTranscriptMetrics.columnWidth, alignment: .leading)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiAgentTranscriptMetrics.controlRadius))
    }
}

enum KajiAgentScrollTarget {
    static let bottom = "kaji-agent-bottom"
}

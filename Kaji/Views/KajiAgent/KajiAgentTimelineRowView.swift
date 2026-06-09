import SwiftUI

struct KajiAgentTimelineRowView: View {
    let row: KajiAgentTimelineRow
    let isToolGroupExpanded: (UUID) -> Bool
    let toggleToolGroup: (UUID) -> Void
    let isToolExpanded: (UUID) -> Bool
    let toggleTool: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if row.startsTurn, let turnID = row.turnID {
                KajiAgentTurnAnchor(id: turnID)
                    .frame(height: 0)
            }
            if row.depth > 0 {
                nestedContent
            } else {
                content
            }
        }
        .id(row.id.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nestedContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(KajiTheme.border.opacity(0.5))
                .frame(width: 1)
                .padding(.leading, CGFloat(row.depth) * 28)
                .padding(.vertical, 8)
            content
                .padding(.leading, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case let .toolGroupHeader(group):
            KajiAgentToolGroupHeaderView(
                group: group,
                isExpanded: isToolGroupExpanded(group.id),
                onToggle: { toggleToolGroup(group.id) }
            )
        case let .tool(message):
            KajiAgentMessageRow(
                message: message,
                toolExpanded: isToolExpanded(message.id),
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
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 760, alignment: .leading)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

enum KajiAgentScrollTarget {
    static let bottom = "kaji-agent-bottom"
}

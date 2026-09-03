import CoreGraphics

enum KajiAgentTimelineRowSpacingPolicy {
    static func topSpacing(for row: KajiAgentTimelineRow) -> CGFloat {
        if row.startsTurn {
            return KajiAgentTranscriptMetrics.turnSpacing
        }
        if row.depth > 0 {
            return 0
        }
        return switch row.kind {
        case .toolGroupHeader:
            KajiAgentTranscriptMetrics.sameTurnSpacing
        case .message:
            KajiAgentTranscriptMetrics.sameTurnSpacing
        case .plan,
             .activity:
            0
        case .thinking:
            0
        case .widget,
             .queuedMessages,
             .user,
             .tool,
             .latestTurnSpacer,
             .bottom:
            0
        }
    }

    static func bottomSpacing(for row: KajiAgentTimelineRow) -> CGFloat {
        if row.depth > 0 {
            return KajiAgentTranscriptMetrics.nestedRowSpacing
        }
        return switch row.kind {
        case .toolGroupHeader:
            4
        case .message:
            2
        case .plan,
             .activity:
            KajiAgentTranscriptMetrics.sameTurnSpacing
        case .thinking:
            KajiAgentTranscriptMetrics.sameTurnSpacing
        case .user:
            KajiAgentTranscriptMetrics.sameTurnSpacing
        case .widget,
             .queuedMessages:
            KajiAgentTranscriptMetrics.sameTurnSpacing
        case .tool,
             .latestTurnSpacer,
             .bottom:
            0
        }
    }
}

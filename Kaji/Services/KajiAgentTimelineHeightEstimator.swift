import CoreGraphics

enum KajiAgentTimelineHeightEstimator {
    static func estimate(_ row: KajiAgentTimelineRow, width: CGFloat = KajiAgentTranscriptMetrics.columnWidth) -> CGFloat {
        switch row.kind {
        case let .widget(lines):
            CGFloat(max(lines.count, 1)) * 17 + 24
        case .queuedMessages:
            42
        case let .user(message):
            textHeight(message.detail, width: min(width, KajiAgentTranscriptMetrics.userWidth)) + 34
        case let .message(message):
            messageHeight(message, width: width)
        case let .plan(plan, expanded):
            planHeight(plan, expanded: expanded)
        case let .activity(activity, expanded):
            activityHeight(activity, expanded: expanded)
        case let .thinking(message, expanded):
            thinkingHeight(message, expanded: expanded)
        case .toolGroupHeader:
            36
        case let .tool(message, expanded):
            toolHeight(message, expanded: expanded)
        case let .latestTurnSpacer(height):
            height
        case .bottom:
            1
        }
    }

    private static func messageHeight(_ message: KajiAgentMessage, width: CGFloat) -> CGFloat {
        switch message.kind {
        case .assistant:
            textHeight(message.detail, width: KajiAgentTranscriptMetrics.proseWidth) + 34
        case .thinking:
            thinkingHeight(message, expanded: false)
        case .event,
             .error:
            textHeight(message.detail, width: width) + 34
        case .tool:
            toolHeight(message, expanded: false)
        case .user:
            textHeight(message.detail, width: min(width, KajiAgentTranscriptMetrics.userWidth)) + 34
        }
    }

    private static func thinkingHeight(_ message: KajiAgentMessage, expanded: Bool) -> CGFloat {
        guard expanded || !message.isComplete else { return 36 }
        return min(textHeight(message.detail, width: KajiAgentTranscriptMetrics.proseWidth), 220) + 46
    }

    private static func planHeight(_ plan: KajiAgentPlanSummary, expanded: Bool) -> CGFloat {
        guard expanded else { return 40 }
        return min(textHeight(plan.summary, width: KajiAgentTranscriptMetrics.proseWidth), 120) + 56
    }

    private static func activityHeight(_ activity: KajiAgentActivitySummary, expanded: Bool) -> CGFloat {
        guard expanded else { return 42 }
        return 54 + CGFloat(activity.actions.count) * 36
    }

    private static func toolHeight(_ message: KajiAgentMessage, expanded: Bool) -> CGFloat {
        var height: CGFloat = 42
        if message.preview != nil || message.fullOutput != nil || message.taskDetails != nil {
            height += 24
        }
        if expanded {
            height += min(textHeight(message.fullOutput ?? message.preview ?? "", width: KajiAgentTranscriptMetrics.columnWidth), 420)
        }
        return height
    }

    private static func textHeight(_ text: String, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 20 }
        let averageCharactersPerLine = max(24, Int(width / 7.2))
        let visualLines = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { count, line in
            count + max(1, Int(ceil(Double(line.count) / Double(averageCharactersPerLine))))
        }
        return min(CGFloat(visualLines) * 22 + 10, 1200)
    }
}

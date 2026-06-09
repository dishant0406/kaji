import CoreGraphics

enum KajiAgentTimelineHeightEstimator {
    static func estimate(_ row: KajiAgentTimelineRow, width: CGFloat = 760) -> CGFloat {
        switch row.kind {
        case let .widget(lines):
            CGFloat(max(lines.count, 1)) * 17 + 24
        case .queuedMessages:
            42
        case let .user(message):
            textHeight(message.detail, width: min(width, 520)) + 28
        case let .message(message):
            messageHeight(message, width: width)
        case .toolGroupHeader:
            36
        case let .tool(message):
            toolHeight(message)
        case let .latestTurnSpacer(height):
            height
        case .bottom:
            1
        }
    }

    private static func messageHeight(_ message: KajiAgentMessage, width: CGFloat) -> CGFloat {
        switch message.kind {
        case .assistant:
            textHeight(message.detail, width: width) + 26
        case .thinking,
             .event,
             .error:
            textHeight(message.detail, width: width) + 34
        case .tool:
            toolHeight(message)
        case .user:
            textHeight(message.detail, width: min(width, 520)) + 28
        }
    }

    private static func toolHeight(_ message: KajiAgentMessage) -> CGFloat {
        var height: CGFloat = 34
        if message.preview != nil || message.fullOutput != nil || message.taskDetails != nil {
            height += 20
        }
        return height
    }

    private static func textHeight(_ text: String, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 20 }
        let averageCharactersPerLine = max(24, Int(width / 7.2))
        let visualLines = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { count, line in
            count + max(1, Int(ceil(Double(line.count) / Double(averageCharactersPerLine))))
        }
        return min(CGFloat(visualLines) * 19 + 8, 1200)
    }
}

import Foundation

@MainActor
enum CodingAgentNotificationCoalescer {
    enum MergeResult {
        case none
        case replaced
        case ignored
    }

    static func merge(_ notification: KajiNotification, into existing: inout [KajiNotification]) -> MergeResult {
        guard shouldCoalesce(notification),
              let latest = existing.first,
              latest.source == notification.source,
              notification.timestamp.timeIntervalSince(latest.timestamp) < 15
        else {
            return .none
        }

        let latestIsGeneric = isGenericTurnCompleted(latest.body)
        let incomingIsGeneric = isGenericTurnCompleted(notification.body)

        if latestIsGeneric, !incomingIsGeneric {
            existing[0] = notification
            return .replaced
        }

        if !latestIsGeneric, incomingIsGeneric {
            return .ignored
        }

        return .none
    }

    private static func shouldCoalesce(_ notification: KajiNotification) -> Bool {
        AIProviderRegistry.shared.notificationPolicy(for: notification.source).coalesceGenericCompletions
    }

    private static func isGenericTurnCompleted(_ body: String) -> Bool {
        let normalized = body.lowercased()
        return normalized == "turn completed" || normalized.hasPrefix("turn completed (")
    }
}

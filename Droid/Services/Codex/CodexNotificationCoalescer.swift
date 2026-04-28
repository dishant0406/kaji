import Foundation

enum CodexNotificationCoalescer {
    enum MergeResult {
        case none
        case replaced
        case ignored
    }

    static func merge(_ notification: DroidNotification, into existing: inout [DroidNotification]) -> MergeResult {
        guard isCodex(notification),
              let latest = existing.first,
              isCodex(latest),
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

    private static func isCodex(_ notification: DroidNotification) -> Bool {
        if case .aiProvider("codex") = notification.source {
            return true
        }
        return false
    }

    private static func isGenericTurnCompleted(_ body: String) -> Bool {
        let normalized = body.lowercased()
        return normalized == "turn completed" || normalized.hasPrefix("turn completed (")
    }
}

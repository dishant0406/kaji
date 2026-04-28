import Foundation

enum CodexNotificationCoalescer {
    static func merge(_ notification: DroidNotification, into existing: inout [DroidNotification]) -> Bool {
        guard isCodex(notification),
              let latest = existing.first,
              isCodex(latest),
              notification.timestamp.timeIntervalSince(latest.timestamp) < 15
        else {
            return false
        }

        let latestIsGeneric = isGenericTurnCompleted(latest.body)
        let incomingIsGeneric = isGenericTurnCompleted(notification.body)

        if latestIsGeneric, !incomingIsGeneric {
            existing[0] = notification
            return true
        }

        if !latestIsGeneric, incomingIsGeneric {
            return true
        }

        return false
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

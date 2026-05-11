import Foundation

enum NotificationDeduplicator {
    static func isDuplicate(_ notification: KajiNotification, in existing: [KajiNotification]) -> Bool {
        guard let latest = existing.first else { return false }
        guard latest.source == notification.source,
              latest.title == notification.title,
              latest.body == notification.body
        else {
            return false
        }

        return notification.timestamp.timeIntervalSince(latest.timestamp) < 5
    }
}

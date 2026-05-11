import Foundation

enum NotificationRouteSoundResolver {
    static func resolve(
        routes: [NotificationRoutingRule],
        event: NotificationOutboundEvent,
        defaultSound: NotificationSound
    ) -> NotificationSound {
        routes.first(where: { $0.matches(event) && $0.sound != nil })?.sound ?? defaultSound
    }
}

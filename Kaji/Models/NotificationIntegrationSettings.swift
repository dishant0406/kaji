import Foundation

struct NotificationIntegrationSettings: Codable, Equatable {
    var destinations: [NotificationDeliveryDestination]
    var routes: [NotificationRoutingRule]

    static let empty = Self(destinations: [], routes: [])
}

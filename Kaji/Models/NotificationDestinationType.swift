import Foundation

enum NotificationDestinationType: String, CaseIterable, Codable, Identifiable {
    case ntfy
    case webhook = "Webhook"

    var id: String { rawValue }
}

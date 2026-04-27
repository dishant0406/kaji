import Foundation

enum NotificationPayloadContentType: String, CaseIterable, Codable, Identifiable {
    case json = "application/json"
    case plainText = "text/plain"

    var id: String { rawValue }
    var label: String { rawValue }
}

import Foundation

enum NotificationRequestMethod: String, CaseIterable, Codable, Identifiable {
    case post = "POST"
    case put = "PUT"

    var id: String { rawValue }
}

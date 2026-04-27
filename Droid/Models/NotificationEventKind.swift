import Foundation

enum NotificationEventKind: String, CaseIterable, Codable, Identifiable {
    case completed = "Completed"
    case attention = "Attention"
    case error = "Error"
    case info = "Info"

    var id: String { rawValue }
}

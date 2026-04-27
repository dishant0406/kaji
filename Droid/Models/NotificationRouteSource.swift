import Foundation

enum NotificationRouteSource: String, CaseIterable, Codable, Identifiable {
    case codex = "Codex"
    case claude = "Claude Code"
    case opencode = "OpenCode"
    case terminal = "Terminal"
    case custom = "Custom"

    var id: String { rawValue }
}

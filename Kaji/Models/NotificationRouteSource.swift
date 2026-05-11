import Foundation

struct NotificationRouteSource: RawRepresentable, CaseIterable, Codable, Hashable, Identifiable {
    static let codex = NotificationRouteSource(rawValue: "Codex")
    static let claude = NotificationRouteSource(rawValue: "Claude Code")
    static let opencode = NotificationRouteSource(rawValue: "OpenCode")
    static let terminal = NotificationRouteSource(rawValue: "Terminal")
    static let custom = NotificationRouteSource(rawValue: "Custom")

    let rawValue: String
    var id: String { rawValue }

    static var allCases: [NotificationRouteSource] {
        CodingAgentRegistry.shared.definitions.map { NotificationRouteSource(rawValue: $0.displayName) } + [.terminal, .custom]
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

import Foundation

struct NotificationRoutingRule: Identifiable, Codable, Equatable {
    struct SourceFilter: RawRepresentable, CaseIterable, Codable, Hashable, Identifiable {
        static let any = SourceFilter(rawValue: "Any Source")
        static let codex = SourceFilter(rawValue: "Codex")
        static let claude = SourceFilter(rawValue: "Claude Code")
        static let opencode = SourceFilter(rawValue: "OpenCode")
        static let terminal = SourceFilter(rawValue: "Terminal")
        static let custom = SourceFilter(rawValue: "Custom")

        let rawValue: String
        var id: String { rawValue }

        static var allCases: [SourceFilter] {
            [.any] + CodingAgentRegistry.shared.definitions.map { SourceFilter(rawValue: $0.displayName) } + [.terminal, .custom]
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

    enum KindFilter: String, CaseIterable, Codable, Identifiable {
        case any = "Any Event"
        case completed = "Completed"
        case attention = "Attention"
        case error = "Error"
        case info = "Info"

        var id: String { rawValue }
    }

    let id: UUID
    var name: String
    var source: SourceFilter
    var eventKind: KindFilter
    var sound: NotificationSound?
    var destinationIDs: [UUID]
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        source: SourceFilter,
        eventKind: KindFilter,
        sound: NotificationSound? = nil,
        destinationIDs: [UUID],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.eventKind = eventKind
        self.sound = sound
        self.destinationIDs = destinationIDs
        self.isEnabled = isEnabled
    }

    func matches(_ event: NotificationOutboundEvent) -> Bool {
        guard isEnabled else { return false }
        let sourceMatches = source == .any || source.rawValue == event.source.rawValue
        let kindMatches = eventKind == .any || eventKind.rawValue == event.kind.rawValue
        return sourceMatches && kindMatches
    }
}

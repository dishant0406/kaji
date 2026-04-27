import Foundation

struct NotificationRoutingRule: Identifiable, Codable, Equatable {
    enum SourceFilter: String, CaseIterable, Codable, Identifiable {
        case any = "Any Source"
        case codex = "Codex"
        case claude = "Claude Code"
        case opencode = "OpenCode"
        case terminal = "Terminal"
        case custom = "Custom"

        var id: String { rawValue }
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
    var destinationIDs: [UUID]
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        source: SourceFilter,
        eventKind: KindFilter,
        destinationIDs: [UUID],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.eventKind = eventKind
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

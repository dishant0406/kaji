import Foundation

enum AgentMissionControlSectionKind: String, CaseIterable, Hashable {
    case needsAttention
    case running
    case failed
    case completed
    case notifications

    var title: String {
        switch self {
        case .needsAttention:
            "Needs Attention"
        case .running:
            "Running"
        case .failed:
            "Failed"
        case .completed:
            "Completed"
        case .notifications:
            "Notifications"
        }
    }
}

struct AgentMissionControlSection: Identifiable, Hashable {
    let kind: AgentMissionControlSectionKind
    let items: [AgentMissionControlItem]

    var id: AgentMissionControlSectionKind { kind }
}

enum AgentMissionControlSectionBuilder {
    static func sections(for items: [AgentMissionControlItem]) -> [AgentMissionControlSection] {
        AgentMissionControlSectionKind.allCases.compactMap { kind in
            let sectionItems = items.filter { sectionKind(for: $0) == kind }
            guard !sectionItems.isEmpty else { return nil }
            return AgentMissionControlSection(kind: kind, items: sectionItems)
        }
    }

    private static func sectionKind(for item: AgentMissionControlItem) -> AgentMissionControlSectionKind {
        if item.id.hasPrefix("notification:") {
            return .notifications
        }
        switch item.status {
        case .needsAttention:
            return .needsAttention
        case .running:
            return .running
        case .failed:
            return .failed
        case .completed,
             .notice:
            return .completed
        }
    }
}

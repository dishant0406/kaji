import Foundation

struct KajiAgentTimelineExpansionState: Hashable {
    static let empty = KajiAgentTimelineExpansionState()

    var toolGroups: Set<UUID> = []
    var thinking: Set<UUID> = []
    var tools: Set<UUID> = []
}

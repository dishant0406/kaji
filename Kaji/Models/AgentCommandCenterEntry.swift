import Foundation

struct AgentCommandCenterEntry: Identifiable, Hashable {
    let id: String
    let item: AgentMissionControlItem
    let category: String
    let title: String
    let detail: String
    let shortcut: String
    let action: AgentCommandCenterAction
}

struct AgentCommandCenterSection: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let status: AgentMissionControlStatus
    let entries: [AgentCommandCenterEntry]
}

enum AgentCommandCenterAction: Hashable {
    case jump
    case reply
    case stop
    case newRun
    case resume
    case verify
    case openFile(AgentChangedFile)
    case openDiff(AgentChangedFile)
}

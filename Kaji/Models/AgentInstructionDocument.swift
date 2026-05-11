import Foundation

enum AgentInstructionScope: String, Hashable {
    case global = "Global"
    case project = "Project"
    case nested = "Nested"
}

struct AgentInstructionDocument: Identifiable, Hashable {
    let id: String
    let agentID: String
    let scope: AgentInstructionScope
    let title: String
    let displayPath: String
    let path: String
    let content: String
}

struct AgentInstructionGroup: Identifiable, Hashable {
    let id: String
    let displayName: String
    let iconName: String
    let documents: [AgentInstructionDocument]
}

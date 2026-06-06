import Foundation

enum KajiModalRoute: Identifiable, Hashable {
    case subagent(KajiAgentSubagentProgress)
    case subagents([KajiAgentSubagentProgress])

    var id: String {
        switch self {
        case let .subagent(agent):
            "subagent:\(agent.id)"
        case let .subagents(agents):
            "subagents:\(agents.map(\.id).joined(separator: ","))"
        }
    }
}

import Foundation

enum KajiModalRoute: Identifiable, Hashable {
    case subagent(KajiAgentSubagentProgress)
    case subagents([KajiAgentSubagentProgress])
    case createPullRequest

    var id: String {
        switch self {
        case let .subagent(agent):
            "subagent:\(agent.id)"
        case let .subagents(agents):
            "subagents:\(agents.map(\.id).joined(separator: ","))"
        case .createPullRequest:
            "create-pull-request"
        }
    }

    var animatedID: String? {
        switch self {
        case .createPullRequest:
            nil
        default:
            id
        }
    }
}

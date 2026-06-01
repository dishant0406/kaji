import Foundation

enum KajiModalRoute: Identifiable, Hashable {
    case subagent(KajiAgentSubagentProgress)

    var id: String {
        switch self {
        case let .subagent(agent):
            "subagent:\(agent.id)"
        }
    }
}

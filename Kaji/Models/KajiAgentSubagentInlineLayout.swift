import Foundation

struct KajiAgentSubagentInlineLayout: Hashable {
    static let maxInlineRows = 3

    let agents: [KajiAgentSubagentProgress]

    init(details: KajiAgentTaskToolDetails) {
        agents = details.visibleAgents
    }

    var inlineAgents: [KajiAgentSubagentProgress] {
        Array(prioritizedAgents.prefix(Self.maxInlineRows))
    }

    var overflowCount: Int {
        max(agents.count - inlineAgents.count, 0)
    }

    var hasOverflow: Bool {
        overflowCount > 0
    }

    var summary: String {
        "\(runningCount) running · \(completedCount) done · \(failedCount) failed"
    }

    private var runningCount: Int {
        agents.count { ["running", "pending", "in_progress"].contains($0.status) }
    }

    private var completedCount: Int {
        agents.count { $0.status == "completed" }
    }

    private var failedCount: Int {
        agents.count { ["failed", "aborted"].contains($0.status) }
    }

    private var prioritizedAgents: [KajiAgentSubagentProgress] {
        agents.sorted {
            let lhsRank = statusRank($0.status)
            let rhsRank = statusRank($1.status)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return $0.index < $1.index
        }
    }

    private func statusRank(_ status: String) -> Int {
        switch status {
        case "running",
             "pending",
             "in_progress": 0
        case "failed",
             "aborted": 1
        case "completed": 2
        default: 3
        }
    }
}

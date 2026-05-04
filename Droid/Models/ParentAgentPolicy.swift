import Foundation

struct ParentAgentSpawnRequest {
    let provider: AskProvider
    let project: Project
    let prompt: String
}

enum ParentAgentPolicyDecision: Equatable {
    case allowed
    case blocked(String, existingRunID: UUID?)
}

@MainActor
enum ParentAgentPolicy {
    static let maxChildRunsPerTask = 8
    static let maxSpawnAttemptsPerTask = 12

    static func decideSpawn(
        task: ParentAgentTask?,
        request: ParentAgentSpawnRequest,
        runs: [AgentRun]
    ) -> ParentAgentPolicyDecision {
        guard let task else { return .allowed }

        let taskRuns = runs.filter { task.childRunIDs.contains($0.id) }
        let activeRuns = taskRuns.filter { isActive($0.status) }
        if let duplicate = duplicateRun(for: request, in: activeRuns) {
            return .blocked(
                "A child agent is already working on this same task. Observe that run instead.",
                existingRunID: duplicate.id
            )
        }

        if task.childRunIDs.count >= maxChildRunsPerTask {
            return .blocked("This parent task has reached the child-agent limit.", existingRunID: taskRuns.last?.id)
        }

        if spawnAttempts(in: task) >= maxSpawnAttemptsPerTask {
            return .blocked("This parent task has reached the spawn-attempt limit.", existingRunID: taskRuns.last?.id)
        }

        return .allowed
    }

    private static func duplicateRun(for request: ParentAgentSpawnRequest, in runs: [AgentRun]) -> AgentRun? {
        let normalizedPrompt = normalized(request.prompt)
        return runs.first { run in
            run.providerID == request.provider.rawValue && normalized(run.title) == normalizedPrompt
        }
    }

    static func fingerprint(for request: ParentAgentSpawnRequest) -> String {
        [request.provider.rawValue, request.project.id.uuidString, normalized(request.prompt)].joined(separator: "|")
    }

    private static func spawnAttempts(in task: ParentAgentTask) -> Int {
        task.spawnFingerprints.count
    }

    private static func isActive(_ status: AgentRunStatus) -> Bool {
        status == .running || status == .waiting || status == .needsAttention
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

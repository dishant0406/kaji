import Foundation

struct ParentAgentSpawnRequest {
    let provider: AskProvider
    let project: Project
    let prompt: String
    let allowParallel: Bool
}

enum ParentAgentPolicyDecision: Equatable {
    case allowed
    case blocked(String, existingRunID: UUID?)
}

@MainActor
enum ParentAgentPolicy {
    static let maxActiveWorkersPerTask = 1
    static let maxChildRunsPerTask = 3
    static let maxSpawnAttemptsPerTask = 4

    static func decideSpawn(
        task: ParentAgentTask?,
        request: ParentAgentSpawnRequest,
        runs: [AgentRun]
    ) -> ParentAgentPolicyDecision {
        guard let task else { return .allowed }

        if !task.spawnFingerprints.isEmpty, !parallelAllowed(task: task, request: request) {
            return .blocked(
                "This parent task already spawned a child agent. Observe that worker before starting another.",
                existingRunID: task.childRunIDs.first
            )
        }

        let taskRuns = runs.filter { task.childRunIDs.contains($0.id) }
        if !taskRuns.isEmpty, !parallelAllowed(task: task, request: request) {
            return .blocked(
                "This parent task already has a child agent. Observe that run instead of spawning another.",
                existingRunID: taskRuns.first?.id
            )
        }

        let activeRuns = taskRuns.filter { isActive($0.status) }
        if !activeRuns.isEmpty, !parallelAllowed(task: task, request: request) {
            return .blocked(
                "A child agent is already running. Observe it before spawning another worker.",
                existingRunID: activeRuns.first?.id
            )
        }

        if taskRuns.count >= maxChildRunsPerTask {
            return .blocked("This parent task has reached the child-agent limit.", existingRunID: taskRuns.last?.id)
        }

        if spawnAttempts(in: task) >= maxSpawnAttemptsPerTask {
            return .blocked("This parent task has reached the spawn-attempt limit.", existingRunID: taskRuns.last?.id)
        }

        if let duplicate = duplicateRun(for: request, in: taskRuns) {
            return .blocked(
                "A child agent has already been assigned this same work. Observe that run instead.",
                existingRunID: duplicate.id
            )
        }

        return .allowed
    }

    private static func parallelAllowed(task: ParentAgentTask, request: ParentAgentSpawnRequest) -> Bool {
        request.allowParallel && userExplicitlyRequestedParallel(task: task)
    }

    private static func userExplicitlyRequestedParallel(task: ParentAgentTask) -> Bool {
        let text = task.timeline
            .filter { $0.kind == .user }
            .map(\.detail)
            .joined(separator: " ")
            .lowercased()
        let markers = [
            "parallel",
            "multiple agents",
            "multi agent",
            "multi-agent",
            "two agents",
            "both agents",
            "run both",
        ]
        return markers.contains { text.contains($0) }
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
        task.timeline.filter { item in
            item.kind == .tool && item.title == "droid.spawn_agent"
        }.count
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

import Foundation
import Testing

@testable import Droid

@Suite("ParentAgentPolicy")
@MainActor
struct ParentAgentPolicyTests {
    @Test("allows a new worker after the previous worker completed")
    func allowsNewWorkerAfterCompletedRun() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let request = spawnRequest(project: project, prompt: "fix input")
        let completedRun = agentRun(project: project, title: "old task", status: .completed)
        var task = ParentAgentTask(prompt: "fix parent agent")
        task.childRunIDs = [completedRun.id]
        task.spawnFingerprints = [ParentAgentPolicy.fingerprint(for: spawnRequest(project: project, prompt: "old task"))]

        let decision = ParentAgentPolicy.decideSpawn(task: task, request: request, runs: [completedRun])

        #expect(decision == .allowed)
    }

    @Test("allows a different worker while an existing worker is active")
    func allowsDifferentWorkerWhileActiveRunExists() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let request = spawnRequest(project: project, prompt: "fix input")
        let runningRun = agentRun(project: project, title: "old task", status: .running)
        var task = ParentAgentTask(prompt: "fix parent agent")
        task.childRunIDs = [runningRun.id]

        let decision = ParentAgentPolicy.decideSpawn(task: task, request: request, runs: [runningRun])

        #expect(decision == .allowed)
    }

    @Test("blocks duplicate work only when the duplicate worker is active")
    func blocksActiveDuplicateWorker() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let request = spawnRequest(project: project, prompt: "fix input")
        let runningRun = agentRun(project: project, title: "fix input", status: .running)
        var task = ParentAgentTask(prompt: "fix parent agent")
        task.childRunIDs = [runningRun.id]
        task.spawnFingerprints = [ParentAgentPolicy.fingerprint(for: request)]

        let decision = ParentAgentPolicy.decideSpawn(task: task, request: request, runs: [runningRun])

        #expect(decision == .blocked(
            "A child agent is already working on this same task. Observe that run instead.",
            existingRunID: runningRun.id
        ))
    }

    private func spawnRequest(project: Project, prompt: String) -> ParentAgentSpawnRequest {
        ParentAgentSpawnRequest(provider: .codex, project: project, prompt: prompt)
    }

    private func agentRun(project: Project, title: String, status: AgentRunStatus) -> AgentRun {
        AgentRun(
            id: UUID(),
            providerID: AskProvider.codex.rawValue,
            paneID: UUID(),
            projectID: project.id,
            worktreeID: UUID(),
            worktreePath: project.path,
            sessionID: nil,
            transcriptPath: nil,
            title: title,
            status: status,
            sourceConfidence: .exactPane,
            changedFiles: [],
            changedFilesAttribution: .none,
            verification: .notStarted,
            startedAt: Date(),
            lastEventAt: Date(),
            events: [],
            actions: []
        )
    }
}

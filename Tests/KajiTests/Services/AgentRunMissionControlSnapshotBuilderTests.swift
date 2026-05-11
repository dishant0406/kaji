import Foundation
import Testing

@testable import Kaji

@MainActor
struct AgentRunMissionControlSnapshotBuilderTests {
    @Test
    func needsAttentionRunsAppearBeforeRunningAndCompleted() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let now = Date(timeIntervalSince1970: 120)

        let items = AgentRunMissionControlSnapshotBuilder.items(
            runs: [
                run(status: .completed, providerID: "codex", project: project, worktree: worktree, start: 10, last: 90),
                run(status: .running, providerID: "claude", project: project, worktree: worktree, start: 20, last: 100),
                run(status: .needsAttention, providerID: "opencode", project: project, worktree: worktree, start: 30, last: 80),
            ],
            notifications: [],
            projects: [project],
            worktrees: [project.id: [worktree]],
            now: now
        )

        #expect(items.map(\.status) == [.needsAttention, .running, .completed])
        #expect(items.first?.providerID == "opencode")
    }

    @Test
    func runRowsIncludeLocationAndRuntime() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let item = AgentRunMissionControlSnapshotBuilder.items(
            runs: [run(status: .running, providerID: "codex", project: project, worktree: worktree, start: 30, last: 90)],
            notifications: [],
            projects: [project],
            worktrees: [project.id: [worktree]],
            now: Date(timeIntervalSince1970: 95)
        ).first

        #expect(item?.title == "Codex session")
        #expect(item?.detail == "muxy / main · 1m")
    }

    @Test
    func runRowsIncludeChangedFilesSummary() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        var agentRun = run(status: .completed, providerID: "codex", project: project, worktree: worktree, start: 30)
        agentRun.changedFiles = [
            .init(path: "A.swift", oldPath: nil, status: .modified, additions: 2, deletions: 1, isBinary: false),
            .init(path: "B.swift", oldPath: nil, status: .added, additions: 8, deletions: 0, isBinary: false),
        ]
        agentRun.changedFilesAttribution = .worktreeSnapshot

        let item = AgentRunMissionControlSnapshotBuilder.items(
            runs: [agentRun],
            notifications: [],
            projects: [project],
            worktrees: [project.id: [worktree]],
            now: Date(timeIntervalSince1970: 95)
        ).first

        #expect(item?.detail == "muxy / main · 1m · 2 files changed snapshot")
        #expect(item?.changedFiles.map(\.path) == ["A.swift", "B.swift"])
        #expect(item?.changedFilesAttribution == .worktreeSnapshot)
    }

    @Test
    func sharedWorktreeRunsDoNotClaimExactChangedFiles() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        var agentRun = run(status: .completed, providerID: "opencode", project: project, worktree: worktree, start: 30)
        agentRun.changedFilesAttribution = .sharedWorktree

        let item = AgentRunMissionControlSnapshotBuilder.items(
            runs: [agentRun],
            notifications: [],
            projects: [project],
            worktrees: [project.id: [worktree]],
            now: Date(timeIntervalSince1970: 95)
        ).first

        #expect(item?.detail == "muxy / main · 1m · shared worktree")
    }

    @Test
    func runRowsIncludeVerificationSummary() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        var agentRun = run(status: .completed, providerID: "codex", project: project, worktree: worktree, start: 30)
        agentRun.verification = AgentVerification(
            status: .passed,
            command: "swift build && swift test",
            output: "ok",
            updatedAt: Date(timeIntervalSince1970: 90)
        )

        let item = AgentRunMissionControlSnapshotBuilder.items(
            runs: [agentRun],
            notifications: [],
            projects: [project],
            worktrees: [project.id: [worktree]],
            now: Date(timeIntervalSince1970: 95)
        ).first

        #expect(item?.detail == "muxy / main · 1m · verified")
        #expect(item?.verification.status == .passed)
        #expect(item?.hasChangedFileEvidence == true)
    }

    @Test
    func runPaneSuppressesFallbackNotificationForSamePane() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let paneID = UUID()
        let items = AgentRunMissionControlSnapshotBuilder.items(
            runs: [run(paneID: paneID, status: .running, providerID: "claude", project: project, worktree: worktree)],
            notifications: [notification(paneID: paneID, project: project, worktree: worktree)],
            projects: [project],
            worktrees: [project.id: [worktree]]
        )

        #expect(items.count == 1)
        #expect(items.first?.id.hasPrefix("run:") == true)
    }

    @Test
    func runContextSuppressesFallbackNotificationForDifferentPane() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let items = AgentRunMissionControlSnapshotBuilder.items(
            runs: [run(status: .completed, providerID: "codex", project: project, worktree: worktree)],
            notifications: [notification(project: project, worktree: worktree)],
            projects: [project],
            worktrees: [project.id: [worktree]]
        )

        #expect(items.count == 1)
        #expect(items.first?.id.hasPrefix("run:") == true)
        #expect(items.first?.status == .completed)
    }

    @Test
    func newerCompletionNotificationOverridesRunningRunStatus() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let paneID = UUID()
        let item = AgentRunMissionControlSnapshotBuilder.items(
            runs: [run(paneID: paneID, status: .running, providerID: "codex", project: project, worktree: worktree, start: 10, last: 11)],
            notifications: [notification(paneID: paneID, project: project, worktree: worktree, timestamp: 12)],
            projects: [project],
            worktrees: [project.id: [worktree]],
            now: Date(timeIntervalSince1970: 20)
        ).first

        #expect(item?.status == .completed)
        #expect(item?.detail.contains("Completed task") == true)
    }

    @Test
    func contextCompletionNotificationOverridesRunningRunStatus() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let item = AgentRunMissionControlSnapshotBuilder.items(
            runs: [run(status: .running, providerID: "codex", project: project, worktree: worktree, start: 10, last: 11)],
            notifications: [notification(project: project, worktree: worktree, timestamp: 12)],
            projects: [project],
            worktrees: [project.id: [worktree]],
            now: Date(timeIntervalSince1970: 20)
        ).first

        #expect(item?.status == .completed)
    }

    @Test
    func providerNotificationWithoutCompletionKeywordsOverridesRunningRunStatus() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let item = AgentRunMissionControlSnapshotBuilder.items(
            runs: [run(status: .running, providerID: "opencode", project: project, worktree: worktree, start: 10, last: 11)],
            notifications: [notification(
                project: project,
                worktree: worktree,
                providerID: "opencode",
                title: "OpenCode",
                body: "Hello.",
                timestamp: 12
            )],
            projects: [project],
            worktrees: [project.id: [worktree]],
            now: Date(timeIntervalSince1970: 20)
        ).first

        #expect(item?.status == .completed)
    }

    @Test
    func detachedNotificationsRemainAsFallbackRows() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let item = AgentRunMissionControlSnapshotBuilder.items(
            runs: [],
            notifications: [notification(project: project, worktree: worktree)],
            projects: [project],
            worktrees: [project.id: [worktree]]
        ).first

        #expect(item?.id.hasPrefix("notification:") == true)
        #expect(item?.status == .completed)
    }

    @Test
    func transcriptEventsBecomePreviewEntries() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        var agentRun = run(status: .running, providerID: "opencode", project: project, worktree: worktree)
        agentRun.events.append(.init(kind: .transcript, label: "tool", text: "Read Package.swift"))
        agentRun.events.append(.init(kind: .attention, label: "attention", text: "Permission requested"))

        let item = AgentRunMissionControlSnapshotBuilder.items(
            runs: [agentRun],
            notifications: [],
            projects: [project],
            worktrees: [project.id: [worktree]]
        ).first

        #expect(item?.transcriptEntries.map(\.kind) == ["tool", "attention"])
        #expect(item?.transcriptEntries.map(\.text) == ["Read Package.swift", "Permission requested"])
    }

    private func run(
        paneID: UUID = UUID(),
        status: AgentRunStatus,
        providerID: String,
        project: Project,
        worktree: Worktree,
        start: TimeInterval = 0,
        last: TimeInterval = 0
    ) -> AgentRun {
        AgentRun(
            id: UUID(),
            providerID: providerID,
            paneID: paneID,
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            title: "",
            status: status,
            sourceConfidence: .exactPane,
            changedFiles: [],
            changedFilesAttribution: .none,
            verification: .notStarted,
            startedAt: Date(timeIntervalSince1970: start),
            lastEventAt: Date(timeIntervalSince1970: last),
            events: [],
            actions: []
        )
    }

    private func notification(
        paneID: UUID = UUID(),
        project: Project,
        worktree: Worktree,
        providerID: String = "codex",
        title: String = "Done",
        body: String = "Completed task",
        timestamp: TimeInterval = 0
    ) -> KajiNotification {
        KajiNotification(
            paneID: paneID,
            projectID: project.id,
            worktreeID: worktree.id,
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: worktree.path,
            source: .aiProvider(providerID),
            title: title,
            body: body,
            timestamp: Date(timeIntervalSince1970: timestamp),
            isRead: true
        )
    }
}

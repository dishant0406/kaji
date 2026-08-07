import Foundation
import Testing

@testable import Kaji

@Suite("Project removal recovery", .serialized)
@MainActor
struct ProjectRemovalRecoveryTests {
    @Test("recovery clears stale tombstone after project state is already gone")
    func recoveryClearsAlreadyRemovedTombstone() async {
        let removed = Project(name: "Removed", path: "/tmp/removed")
        let remaining = Project(name: "Remaining", path: "/tmp/remaining")
        let remainingWorktree = Worktree(name: "Remaining", path: remaining.path, isPrimary: true)
        let tombstones = ProjectRemovalRecoveryTombstones(records: [
            ProjectRemovalTombstone(
                project: removed,
                worktrees: [Worktree(name: "Removed", path: removed.path, isPrimary: true)],
                cleanupOnDisk: true
            ),
        ])
        let projectStore = ProjectStore(persistence: ProjectRemovalRecoveryProjectPersistence(projects: [remaining]))
        let worktreeStore = WorktreeStore(
            persistence: ProjectRemovalRecoveryWorktreePersistence(worktrees: [remaining.id: [remainingWorktree]]),
            projects: [remaining]
        )
        let appState = AppState(
            selectionStore: ProjectRemovalRecoverySelectionStore(),
            terminalViews: ProjectRemovalRecoveryTerminalViews(),
            workspacePersistence: ProjectRemovalRecoveryWorkspacePersistence()
        )
        let service = ProjectRemovalService(
            tombstones: tombstones,
            quiesceIndexes: { _ in },
            cleanupDisk: { _, _ in true }
        )

        await service.recoverPendingRemovals(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )

        #expect(tombstones.records.isEmpty)
        #expect(projectStore.projects == [remaining])
        #expect(worktreeStore.list(for: remaining.id) == [remainingWorktree])
    }

    @Test("failed recovery increments retry count and keeps the tombstone")
    func failedRecoveryIncrementsRetryCount() async {
        let removed = Project(name: "Removed", path: "/tmp/removed")
        let worktree = Worktree(name: "Removed", path: removed.path, isPrimary: false)
        let tombstones = ProjectRemovalRecoveryTombstones(records: [
            ProjectRemovalTombstone(project: removed, worktrees: [worktree], cleanupOnDisk: true, retryCount: 1),
        ])
        let projectStore = ProjectStore(persistence: ProjectRemovalRecoveryProjectPersistence(projects: []))
        let worktreeStore = WorktreeStore(
            persistence: ProjectRemovalRecoveryWorktreePersistence(worktrees: [:]),
            projects: []
        )
        let appState = AppState(
            selectionStore: ProjectRemovalRecoverySelectionStore(),
            terminalViews: ProjectRemovalRecoveryTerminalViews(),
            workspacePersistence: ProjectRemovalRecoveryWorkspacePersistence()
        )
        let service = ProjectRemovalService(
            tombstones: tombstones,
            quiesceIndexes: { _ in },
            cleanupDisk: { _, _ in false }
        )

        await service.recoverPendingRemovals(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )

        #expect(tombstones.records.count == 1)
        #expect(tombstones.records.first?.retryCount == 2)
        #expect(!tombstones.quarantined)
    }

    @Test("recovery quarantines tombstone after max retries")
    func recoveryQuarantinesAfterMaxRetries() async {
        let removed = Project(name: "Removed", path: "/tmp/removed")
        let worktree = Worktree(name: "Removed", path: removed.path, isPrimary: false)
        let tombstones = ProjectRemovalRecoveryTombstones(records: [
            ProjectRemovalTombstone(
                project: removed,
                worktrees: [worktree],
                cleanupOnDisk: true,
                retryCount: ProjectRemovalService.maxRetryCount - 1
            ),
        ])
        let projectStore = ProjectStore(persistence: ProjectRemovalRecoveryProjectPersistence(projects: []))
        let worktreeStore = WorktreeStore(
            persistence: ProjectRemovalRecoveryWorktreePersistence(worktrees: [:]),
            projects: []
        )
        let appState = AppState(
            selectionStore: ProjectRemovalRecoverySelectionStore(),
            terminalViews: ProjectRemovalRecoveryTerminalViews(),
            workspacePersistence: ProjectRemovalRecoveryWorkspacePersistence()
        )
        let service = ProjectRemovalService(
            tombstones: tombstones,
            quiesceIndexes: { _ in },
            cleanupDisk: { _, _ in false }
        )

        await service.recoverPendingRemovals(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )

        #expect(tombstones.records.isEmpty)
        #expect(tombstones.quarantined)
    }

    @Test("legacy tombstones without retryCount decode as zero")
    func legacyTombstoneDecodesWithZeroRetries() throws {
        let data = Data("""
        [
          {
            "cleanupOnDisk" : true,
            "project" : {
              "createdAt" : 806671262.228424,
              "id" : "4DBBFC54-CEBA-4219-85EE-0C892E6F01F0",
              "name" : "dauntless",
              "path" : "/Users/dishants/projects/dauntless",
              "sortOrder" : 10
            },
            "worktrees" : [
              {
                "backend" : "primary",
                "createdAt" : 806671262.231373,
                "id" : "780EA42E-58C4-40F8-A440-94F7A659D4B5",
                "isPrimary" : true,
                "name" : "dauntless",
                "path" : "/Users/dishants/projects/dauntless",
                "source" : "kaji"
              }
            ]
          }
        ]
        """.utf8)

        let tombstones = try JSONDecoder().decode([ProjectRemovalTombstone].self, from: data)

        #expect(tombstones.count == 1)
        #expect(tombstones.first?.retryCount == 0)
        #expect(tombstones.first?.cleanupOnDisk == true)
    }
}

private final class ProjectRemovalRecoveryTombstones: ProjectRemovalTombstonePersisting {
    var records: [ProjectRemovalTombstone]
    var quarantined = false

    init(records: [ProjectRemovalTombstone]) {
        self.records = records
    }

    func load() throws -> [ProjectRemovalTombstone] {
        records
    }

    func save(_ tombstones: [ProjectRemovalTombstone]) throws {
        records = tombstones
    }

    func quarantine() throws {
        quarantined = true
        records.removeAll()
    }
}

private final class ProjectRemovalRecoveryProjectPersistence: ProjectPersisting {
    var projects: [Project]

    init(projects: [Project]) {
        self.projects = projects
    }

    func loadProjects() throws -> [Project] {
        projects
    }

    func saveProjects(_ projects: [Project]) throws {
        self.projects = projects
    }
}

private final class ProjectRemovalRecoveryWorktreePersistence: WorktreePersisting {
    var worktrees: [UUID: [Worktree]]

    init(worktrees: [UUID: [Worktree]]) {
        self.worktrees = worktrees
    }

    func loadWorktrees(projectID: UUID) throws -> [Worktree] {
        worktrees[projectID] ?? []
    }

    func saveWorktrees(_ worktrees: [Worktree], projectID: UUID) throws {
        self.worktrees[projectID] = worktrees
    }

    func removeWorktrees(projectID: UUID) throws {
        worktrees.removeValue(forKey: projectID)
    }
}

private final class ProjectRemovalRecoverySelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

private final class ProjectRemovalRecoveryTerminalViews: TerminalViewRemoving {
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for _: UUID) -> Bool { false }
}

private final class ProjectRemovalRecoveryWorkspacePersistence: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_: [WorkspaceSnapshot]) throws {}
}

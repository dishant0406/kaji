import Foundation
import Testing

@testable import Droid

@MainActor
struct AgentMissionControlSnapshotBuilderTests {
    @Test
    func runningActivitiesAppearBeforeCompletedNotifications() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let activity = AIActivityStore.Activity(
            paneID: UUID(),
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            providerID: "codex",
            startedAt: Date(timeIntervalSince1970: 2)
        )
        let notification = notification(
            project: project,
            worktree: worktree,
            source: .aiProvider("claude"),
            title: "Done",
            body: "Completed task",
            isRead: true
        )

        let items = AgentMissionControlSnapshotBuilder.items(
            activities: [activity],
            notifications: [notification],
            projects: [project],
            worktrees: [project.id: [worktree]]
        )

        #expect(items.map(\.status) == [.running, .completed])
        #expect(items.first?.detail == "muxy / main")
    }

    @Test
    func unreadProviderNotificationsNeedAttention() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let item = AgentMissionControlSnapshotBuilder.items(
            activities: [],
            notifications: [notification(
                project: project,
                worktree: worktree,
                source: .aiProvider("opencode"),
                title: "Question",
                body: "Pick an option",
                isRead: false
            )],
            projects: [project],
            worktrees: [project.id: [worktree]]
        ).first

        #expect(item?.status == .needsAttention)
        #expect(item?.providerName == "OpenCode")
        #expect(item?.providerIconName == "opencode")
    }

    @Test
    func activePaneSuppressesOlderNotificationForSamePane() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let paneID = UUID()
        let activity = AIActivityStore.Activity(
            paneID: paneID,
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            providerID: "codex",
            startedAt: Date()
        )
        let notification = notification(
            paneID: paneID,
            project: project,
            worktree: worktree,
            source: .aiProvider("codex"),
            title: "Done",
            body: "Completed task",
            isRead: true
        )

        let items = AgentMissionControlSnapshotBuilder.items(
            activities: [activity],
            notifications: [notification],
            projects: [project],
            worktrees: [project.id: [worktree]]
        )

        #expect(items.count == 1)
        #expect(items.first?.status == .running)
    }

    @Test
    func runningActivitiesIncludeTranscriptEntries() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let activity = AIActivityStore.Activity(
            paneID: UUID(),
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            providerID: "claude",
            startedAt: Date(),
            transcriptEntries: [AgentTranscriptEntry(kind: "user", text: "Fix tests")]
        )

        let item = AgentMissionControlSnapshotBuilder.items(
            activities: [activity],
            notifications: [],
            projects: [project],
            worktrees: [project.id: [worktree]]
        ).first

        #expect(item?.transcriptEntries.first?.kind == "user")
        #expect(item?.transcriptEntries.first?.text == "Fix tests")
    }

    private func notification(
        paneID: UUID = UUID(),
        project: Project,
        worktree: Worktree,
        source: DroidNotification.Source,
        title: String,
        body: String,
        isRead: Bool
    ) -> DroidNotification {
        DroidNotification(
            paneID: paneID,
            projectID: project.id,
            worktreeID: worktree.id,
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: worktree.path,
            source: source,
            title: title,
            body: body,
            isRead: isRead
        )
    }
}

import Foundation
import Testing

@testable import Kaji

@MainActor
struct KajiAgentActivityBridgeTests {
    @Test
    func startCreatesRunningKajiAgentActivityAndRun() throws {
        let fixture = ActivityBridgeFixture()
        fixture.resetStores()

        KajiAgentActivityBridge.shared.start(
            scope: fixture.scope,
            appState: fixture.appState,
            worktreeStore: fixture.worktreeStore,
            sessionID: "session-1"
        )

        let activity = try #require(AIActivityStore.shared.activitiesByPaneID[fixture.agentID])
        #expect(activity.providerID == AgentProviderCatalog.kajiAgentID)
        #expect(activity.projectID == fixture.project.id)
        #expect(activity.worktreeID == fixture.worktree.id)
        #expect(AIActivityStore.shared.hasActiveAgent(projectID: fixture.project.id, worktreeID: fixture.worktree.id))
        let run = try #require(AgentRunStore.shared.run(providerID: AgentProviderCatalog.kajiAgentID, paneID: fixture.agentID))
        #expect(run.status == .running)
        #expect(run.title == "Kaji Agent")
        #expect(run.sessionID == "session-1")
    }

    @Test
    func completionAddsContextNotificationAndClearsOnlyMatchingActivity() throws {
        let fixture = ActivityBridgeFixture()
        fixture.resetStores()
        let siblingAgentID = UUID()

        KajiAgentActivityBridge.shared.start(
            scope: fixture.scope,
            appState: fixture.appState,
            worktreeStore: fixture.worktreeStore,
            sessionID: "session-1"
        )
        AIActivityStore.shared.start(
            providerID: AgentProviderCatalog.kajiAgentID,
            paneID: siblingAgentID,
            projectID: fixture.project.id,
            worktreeID: fixture.worktree.id,
            worktreePath: fixture.worktree.path
        )

        KajiAgentActivityBridge.shared.complete(
            scope: fixture.scope,
            appState: fixture.appState,
            worktreeStore: fixture.worktreeStore,
            body: "Implemented the requested change",
            sessionID: "session-1"
        )

        #expect(AIActivityStore.shared.activitiesByPaneID[fixture.agentID] == nil)
        #expect(AIActivityStore.shared.activitiesByPaneID[siblingAgentID] != nil)
        let notification = try #require(NotificationStore.shared.notifications.first)
        #expect(notification.paneID == fixture.agentID)
        #expect(notification.source == .aiProvider(AgentProviderCatalog.kajiAgentID))
        #expect(notification.projectID == fixture.project.id)
        #expect(notification.worktreeID == fixture.worktree.id)
        #expect(notification.tabID == fixture.workspaceTab.id)
        let run = try #require(AgentRunStore.shared.run(providerID: AgentProviderCatalog.kajiAgentID, paneID: fixture.agentID))
        #expect(run.status == .completed)
        #expect(run.events.contains { $0.label == "done" && $0.text == "Implemented the requested change" })
    }

    @Test
    func attentionRecordsRunAttentionAndAddsNotification() throws {
        let fixture = ActivityBridgeFixture()
        fixture.resetStores()
        KajiAgentActivityBridge.shared.start(
            scope: fixture.scope,
            appState: fixture.appState,
            worktreeStore: fixture.worktreeStore,
            sessionID: nil
        )

        KajiAgentActivityBridge.shared.needsAttention(
            scope: fixture.scope,
            appState: fixture.appState,
            worktreeStore: fixture.worktreeStore,
            kind: "approval",
            detail: "Allow edit?"
        )

        let run = try #require(AgentRunStore.shared.run(providerID: AgentProviderCatalog.kajiAgentID, paneID: fixture.agentID))
        #expect(run.status == .needsAttention)
        #expect(run.events.contains { $0.kind == .attention && $0.text == "Allow edit?" })
        let event = NotificationEventNormalizer.normalize(
            notification: try #require(NotificationStore.shared.notifications.first),
            appState: fixture.appState,
            worktreeStore: fixture.worktreeStore
        )
        #expect(event.source.rawValue == "Kaji Agent")
        #expect(event.kind == .attention)
    }

    @Test
    func observeAddsBoundedTranscriptEntries() throws {
        let fixture = ActivityBridgeFixture()
        fixture.resetStores()
        KajiAgentActivityBridge.shared.start(
            scope: fixture.scope,
            appState: fixture.appState,
            worktreeStore: fixture.worktreeStore,
            sessionID: nil
        )

        KajiAgentActivityBridge.shared.observe(
            scope: fixture.scope,
            event: KajiAgentSessionEvent(type: "tool_execution_start", toolName: "edit")
        )

        let run = try #require(AgentRunStore.shared.run(providerID: AgentProviderCatalog.kajiAgentID, paneID: fixture.agentID))
        #expect(run.events.contains { $0.label == "tool" && $0.text == "Running edit" })
    }
}

@MainActor
private struct ActivityBridgeFixture {
    let project = Project(name: "muxy", path: "/tmp/muxy")
    let worktree: Worktree
    let agentID = UUID()
    let appState: AppState
    let worktreeStore: WorktreeStore
    let workspaceTab: WorkspaceTab
    let scope: KajiAgentScope

    init() {
        worktree = Worktree(name: "main", path: project.path, isPrimary: true)
        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        let area = TabArea(
            projectPath: project.path,
            existingTab: TerminalTab(parentAgentState: ParentAgentTabState(
                id: agentID,
                projectID: project.id,
                worktreeID: worktree.id,
                projectPath: project.path
            ))
        )
        workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        appState = AppState(
            selectionStore: ActivityBridgeSelectionStore(),
            terminalViews: ActivityBridgeTerminalViews(),
            workspacePersistence: ActivityBridgeWorkspacePersistence()
        )
        appState.activeProjectID = project.id
        appState.activeWorktreeID = [project.id: worktree.id]
        appState.activeWorktreePath = [project.id: project.path]
        appState.workspaces = [key: WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)]
        appState.workspaceRoots = [key: workspaceTab.root]
        appState.focusedAreaID = [key: area.id]
        worktreeStore = WorktreeStore(
            persistence: ActivityBridgeWorktreePersistence(worktrees: [project.id: [worktree]]),
            projects: [project]
        )
        scope = KajiAgentScope(agentID: agentID, projectID: project.id, worktreeID: worktree.id, projectPath: project.path)
    }

    func resetStores() {
        AIActivityStore.shared.reset()
        NotificationStore.shared.clear()
        NotificationStore.shared.appState = appState
        NotificationStore.shared.worktreeStore = worktreeStore
        UserDefaults.standard.set(NotificationSound.none.rawValue, forKey: "kaji.notifications.sound")
    }
}

private struct ActivityBridgeSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

private struct ActivityBridgeTerminalViews: TerminalViewRemoving {
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for _: UUID) -> Bool { false }
}

private struct ActivityBridgeWorkspacePersistence: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_: [WorkspaceSnapshot]) throws {}
}

private struct ActivityBridgeWorktreePersistence: WorktreePersisting {
    let worktrees: [UUID: [Worktree]]

    func loadWorktrees(projectID: UUID) throws -> [Worktree] {
        worktrees[projectID] ?? []
    }

    func saveWorktrees(_: [Worktree], projectID _: UUID) throws {}
    func removeWorktrees(projectID _: UUID) throws {}
}

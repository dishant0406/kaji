import Foundation
import Testing

@testable import Droid

@MainActor
struct ResourceMonitorTests {
    @Test
    func locatorFindsTerminalPanesAcrossWorkspaceTabs() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: project.id, worktreeID: worktreeID)

        let firstPane = TerminalPaneState(projectPath: project.path, title: "shell")
        let firstArea = TabArea(projectPath: project.path, existingTab: TerminalTab(pane: firstPane))

        let secondPane = TerminalPaneState(projectPath: project.path, title: "server")
        let secondArea = TabArea(projectPath: project.path, existingTab: TerminalTab(pane: secondPane))

        let firstWorkspaceTab = WorkspaceTab(root: .tabArea(firstArea), focusedAreaID: firstArea.id)
        let secondWorkspaceTab = WorkspaceTab(root: .tabArea(secondArea), focusedAreaID: secondArea.id)
        let workspace = WorktreeWorkspace(tabs: [firstWorkspaceTab, secondWorkspaceTab], activeTabID: firstWorkspaceTab.id)

        let appState = AppState(
            selectionStore: ResourceMonitorStubSelectionStore(),
            terminalViews: ResourceMonitorStubTerminalViews(),
            workspacePersistence: ResourceMonitorStubWorkspacePersistence()
        )
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = worktreeID
        appState.activeWorktreePath[project.id] = project.path
        appState.workspaces[key] = workspace

        let descriptors = ResourceMonitorTerminalLocator.locate(appState: appState, projects: [project])

        #expect(descriptors.count == 2)
        #expect(Set(descriptors.map(\.title)) == ["shell", "server"])
        #expect(Set(descriptors.map(\.projectName)) == ["muxy"])
    }

    @Test
    func locatorCompactsPathLikeTerminalTitlesToFolderNames() {
        let project = Project(name: "muxy", path: "/tmp/worktrees/muxy")
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: project.id, worktreeID: worktreeID)

        let pane = TerminalPaneState(projectPath: project.path, title: "/tmp/worktrees/muxy")
        let area = TabArea(projectPath: project.path, existingTab: TerminalTab(pane: pane))
        let workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let workspace = WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)

        let appState = AppState(
            selectionStore: ResourceMonitorStubSelectionStore(),
            terminalViews: ResourceMonitorStubTerminalViews(),
            workspacePersistence: ResourceMonitorStubWorkspacePersistence()
        )
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = worktreeID
        appState.activeWorktreePath[project.id] = project.path
        appState.workspaces[key] = workspace

        let descriptors = ResourceMonitorTerminalLocator.locate(appState: appState, projects: [project])

        #expect(descriptors.map(\.title) == ["muxy"])
    }

    @Test
    func aggregatorSumsProjectUsageAndSortsTerminalsByCPU() {
        let alpha = Project(name: "alpha", path: "/tmp/alpha")
        let beta = Project(name: "beta", path: "/tmp/beta")

        let alphaReadings = [
            ResourceMonitorTerminalReading(
                descriptor: .init(
                    paneID: UUID(),
                    tabID: UUID(),
                    areaID: UUID(),
                    projectID: alpha.id,
                    projectName: alpha.name,
                    title: "compile"
                ),
                processGroupID: 101,
                pid: 101,
                processName: "swift",
                ttyName: "ttys001",
                cpuPercent: 82,
                memoryBytes: 800 * 1_024 * 1_024,
                threadCount: 10
            ),
            ResourceMonitorTerminalReading(
                descriptor: .init(
                    paneID: UUID(),
                    tabID: UUID(),
                    areaID: UUID(),
                    projectID: alpha.id,
                    projectName: alpha.name,
                    title: "shell"
                ),
                processGroupID: 102,
                pid: 102,
                processName: "zsh",
                ttyName: "ttys002",
                cpuPercent: 6,
                memoryBytes: 120 * 1_024 * 1_024,
                threadCount: 2
            )
        ]

        let betaReading = ResourceMonitorTerminalReading(
            descriptor: .init(
                paneID: UUID(),
                tabID: UUID(),
                areaID: UUID(),
                projectID: beta.id,
                projectName: beta.name,
                title: "agent"
            ),
            processGroupID: 201,
            pid: 201,
            processName: "codex",
            ttyName: "ttys010",
            cpuPercent: 24,
            memoryBytes: 512 * 1_024 * 1_024,
            threadCount: 6
        )

        let projects = ResourceMonitorAggregator.buildProjects(
            from: alphaReadings + [betaReading],
            orderedProjects: [alpha, beta]
        )

        #expect(projects.map { $0.name } == ["alpha", "beta"])
        #expect(projects[0].cpuPercent == 88)
        #expect(projects[0].memoryBytes == UInt64(920 * 1_024 * 1_024))
        #expect(projects[0].terminals.map { $0.title } == ["compile", "shell"])
    }

    @Test
    func closeMonitoredTerminalRemovesInnerAreaTabAndPaneView() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: project.id, worktreeID: worktreeID)

        let primaryPane = TerminalPaneState(projectPath: project.path, title: "shell")
        let primaryTab = TerminalTab(pane: primaryPane)
        let area = TabArea(projectPath: project.path, existingTab: primaryTab)

        let secondaryPane = TerminalPaneState(projectPath: project.path, title: "server")
        let secondaryTab = TerminalTab(pane: secondaryPane)
        area.insertExistingTab(secondaryTab)

        let workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let workspace = WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)

        let terminalViews = ResourceMonitorTrackingTerminalViews()
        let appState = AppState(
            selectionStore: ResourceMonitorStubSelectionStore(),
            terminalViews: terminalViews,
            workspacePersistence: ResourceMonitorStubWorkspacePersistence()
        )
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = worktreeID
        appState.activeWorktreePath[project.id] = project.path
        appState.workspaces[key] = workspace
        appState.workspaceRoots[key] = workspaceTab.root
        appState.focusedAreaID[key] = area.id

        appState.closeMonitoredTerminal(secondaryTab.id, areaID: area.id, projectID: project.id)

        #expect(area.tabs.count == 1)
        #expect(area.tabs.map(\.id) == [primaryTab.id])
        #expect(terminalViews.removedPaneIDs == [secondaryPane.id])
    }
}

private struct ResourceMonitorStubSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

private struct ResourceMonitorStubTerminalViews: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

@MainActor
private final class ResourceMonitorTrackingTerminalViews: TerminalViewRemoving {
    private(set) var removedPaneIDs: [UUID] = []

    func removeView(for paneID: UUID) {
        removedPaneIDs.append(paneID)
    }

    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private struct ResourceMonitorStubWorkspacePersistence: WorkspacePersisting {
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
}

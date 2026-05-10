import Foundation
import os
import SwiftUI

private let logger = Logger(subsystem: "app.droid", category: "AppState")

@MainActor
@Observable
final class AppState {
    struct SplitAreaRequest {
        let projectID: UUID
        let areaID: UUID
        let direction: SplitDirection
        let position: SplitPosition
    }

    struct DiffViewerRequest {
        let vcs: VCSTabState
        let filePath: String
        let isStaged: Bool
    }

    struct CodeGraphTabRequest {
        let projectID: UUID
        let worktreeID: UUID
        let worktreePath: String
        let graphURL: URL
    }

    enum Action {
        case selectProject(projectID: UUID, worktreeID: UUID, worktreePath: String)
        case selectWorktree(projectID: UUID, worktreeID: UUID, worktreePath: String)
        case removeProject(projectID: UUID)
        case removeWorktree(
            projectID: UUID,
            worktreeID: UUID,
            replacementWorktreeID: UUID?,
            replacementWorktreePath: String?
        )
        case createTab(projectID: UUID, areaID: UUID?)
        case createTabInDirectory(projectID: UUID, areaID: UUID?, directory: String)
        case createCommandTab(projectID: UUID, areaID: UUID?, title: String, command: String)
        case createStartupCommandTab(StartupCommandTabRequest)
        case createCommandSplit(projectID: UUID, title: String, command: String)
        case createVCSTab(projectID: UUID, areaID: UUID?)
        case createParentAgentTab(projectID: UUID, areaID: UUID?)
        case createCodeGraphTab(CodeGraphTabRequest)
        case createBrowserSplit(projectID: UUID)
        case createEditorTab(projectID: UUID, areaID: UUID?, filePath: String)
        case createExternalEditorTab(projectID: UUID, areaID: UUID?, filePath: String, command: String)
        case createDiffViewerTab(projectID: UUID, areaID: UUID?, request: DiffViewerRequest)
        case closeTab(projectID: UUID, areaID: UUID, tabID: UUID)
        case selectTab(projectID: UUID, areaID: UUID, tabID: UUID)
        case selectTabByIndex(projectID: UUID, areaID: UUID?, index: Int)
        case selectNextTab(projectID: UUID)
        case selectPreviousTab(projectID: UUID)
        case splitArea(SplitAreaRequest)
        case closeArea(projectID: UUID, areaID: UUID)
        case focusArea(projectID: UUID, areaID: UUID)
        case focusPaneLeft(projectID: UUID)
        case focusPaneRight(projectID: UUID)
        case focusPaneUp(projectID: UUID)
        case focusPaneDown(projectID: UUID)
        case moveTab(projectID: UUID, request: TabMoveRequest)
        case movePane(projectID: UUID, request: PaneMoveRequest)
        case selectNextProject(projects: [Project], worktrees: [UUID: [Worktree]])
        case selectPreviousProject(projects: [Project], worktrees: [UUID: [Worktree]])
        case navigate(projectID: UUID, worktreeID: UUID, areaID: UUID, tabID: UUID?)
    }

    private let selectionStore: any ActiveProjectSelectionStoring
    private let terminalViews: any TerminalViewRemoving
    private let workspacePersistence: any WorkspacePersisting
    var onProjectsEmptied: (([UUID]) -> Void)?

    var activeProjectID: UUID?
    var isParentAgentHomePresented = false

    var activeWorktreeID: [UUID: UUID] = [:]
    var activeWorktreePath: [UUID: String] = [:]

    struct PendingTabClose: Equatable {
        let projectID: UUID
        let areaID: UUID
        let tabID: UUID
    }

    struct StartupCommandTabRequest {
        let projectID: UUID
        let areaID: UUID?
        let title: String
        let command: String
        let seed: CodingAgentSessionSeed?
    }

    var workspaces: [WorktreeKey: WorktreeWorkspace] = [:]
    var workspaceRoots: [WorktreeKey: SplitNode] = [:]
    var focusedAreaID: [WorktreeKey: UUID] = [:]
    var pendingLastTabClose: PendingTabClose?
    var pendingUnsavedEditorTabClose: PendingTabClose?
    var pendingProcessTabClose: PendingTabClose?
    var pendingSaveErrorMessage: String?
    let navigation = NavigationHistory()
    private var focusHistory: [WorktreeKey: [UUID]] = [:]

    init(
        selectionStore: any ActiveProjectSelectionStoring,
        terminalViews: any TerminalViewRemoving,
        workspacePersistence: any WorkspacePersisting
    ) {
        self.selectionStore = selectionStore
        self.terminalViews = terminalViews
        self.workspacePersistence = workspacePersistence
    }

    func restoreSelection(projects: [Project], worktrees: [UUID: [Worktree]]) {
        let snapshots: [WorkspaceSnapshot]
        do {
            snapshots = try workspacePersistence.loadWorkspaces()
        } catch {
            logger.error("Failed to load workspaces: \(error)")
            snapshots = []
        }
        let restored = WorkspaceRestorer.restoreAll(
            from: snapshots,
            projects: projects,
            worktrees: worktrees
        )
        for entry in restored {
            workspaces[entry.key] = entry.workspace
        }
        refreshWorkspaceMirrors()

        let savedWorktreeIDs = selectionStore.loadActiveWorktreeIDs()
        for project in projects {
            let restoredKeysForProject = restored.map(\.key).filter { $0.projectID == project.id }
            let availableWorktrees = worktrees[project.id] ?? []
            if let savedWorktreeID = savedWorktreeIDs[project.id],
               let savedWorktree = availableWorktrees.first(where: { $0.id == savedWorktreeID })
            {
                activeWorktreeID[project.id] = savedWorktreeID
                activeWorktreePath[project.id] = savedWorktree.path
                continue
            }
            guard let restoredKey = restoredKeysForProject.first else { continue }
            activeWorktreeID[project.id] = restoredKey.worktreeID
            activeWorktreePath[project.id] = resolvedWorktreePath(
                projectID: project.id,
                worktreeID: restoredKey.worktreeID,
                worktrees: worktrees
            )
        }

        guard let id = selectionStore.loadActiveProjectID(),
              projects.contains(where: { $0.id == id }),
              activeWorktreeID[id] != nil
        else { return }
        activeProjectID = id
        recordCurrentNavigationEntry()
    }

    func saveWorkspaces() {
        let snapshots = WorkspaceRestorer.snapshotAll(
            workspaces: workspaces
        )
        do {
            try workspacePersistence.saveWorkspaces(snapshots)
        } catch {
            logger.error("Failed to save workspaces: \(error)")
        }
    }

    private func saveSelection() {
        selectionStore.saveActiveProjectID(activeProjectID)
        selectionStore.saveActiveWorktreeIDs(activeWorktreeID)
    }

    func activeWorktreeKey(for projectID: UUID) -> WorktreeKey? {
        guard let worktreeID = activeWorktreeID[projectID] else { return nil }
        return WorktreeKey(projectID: projectID, worktreeID: worktreeID)
    }

    func workspaceRoot(for projectID: UUID) -> SplitNode? {
        guard let key = activeWorktreeKey(for: projectID) else { return nil }
        return workspaceRoots[key]
    }

    func workspace(for projectID: UUID) -> WorktreeWorkspace? {
        guard let key = activeWorktreeKey(for: projectID) else { return nil }
        return workspaces[key]
    }

    func workspaceTabs(for projectID: UUID) -> [WorkspaceTab] {
        workspace(for: projectID)?.tabs ?? []
    }

    func activeWorkspaceTab(for projectID: UUID) -> WorkspaceTab? {
        workspace(for: projectID)?.activeTab
    }

    func focusedAreaID(for projectID: UUID) -> UUID? {
        guard let key = activeWorktreeKey(for: projectID) else { return nil }
        return focusedAreaID[key]
    }

    func showParentAgentHome() {
        isParentAgentHomePresented = true
    }

    func hideParentAgentHome() {
        isParentAgentHomePresented = false
    }

    func selectProject(_ project: Project, worktree: Worktree) {
        dispatch(.selectProject(
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path
        ))
    }

    func selectWorktree(projectID: UUID, worktree: Worktree) {
        dispatch(.selectWorktree(
            projectID: projectID,
            worktreeID: worktree.id,
            worktreePath: worktree.path
        ))
    }

    func focusedArea(for projectID: UUID) -> TabArea? {
        activeWorkspaceTab(for: projectID)?.activeArea
    }

    func allAreas(for projectID: UUID) -> [TabArea] {
        workspaceTabs(for: projectID).flatMap { $0.root.allAreas() }
    }

    func splitFocusedArea(direction: SplitDirection, projectID: UUID) {
        guard let area = focusedArea(for: projectID) else { return }
        dispatch(.splitArea(.init(
            projectID: projectID,
            areaID: area.id,
            direction: direction,
            position: .second
        )))
    }

    func closeArea(_ areaID: UUID, projectID: UUID) {
        dispatch(.closeArea(projectID: projectID, areaID: areaID))
    }

    func createTab(projectID: UUID) {
        dispatch(.createTab(projectID: projectID, areaID: nil))
    }

    func createVCSTab(projectID: UUID) {
        dispatch(.createVCSTab(projectID: projectID, areaID: nil))
    }

    func openParentAgentTab(projectID: UUID) {
        for workspaceTab in workspaceTabs(for: projectID) where workspaceTab.root.allAreas().contains(where: { area in
            area.tabs.contains(where: { $0.kind == .parentAgent })
        }) {
            activateWorkspaceTab(workspaceTab.id, projectID: projectID)
            return
        }
        dispatch(.createParentAgentTab(projectID: projectID, areaID: nil))
    }

    func openCodeGraphTab(projectID: UUID, worktreeID: UUID, worktreePath: String, graphURL: URL) {
        dispatch(.createCodeGraphTab(CodeGraphTabRequest(
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: worktreePath,
            graphURL: graphURL
        )))
    }

    func openBrowserPanel(projectID: UUID) {
        guard BrowserExtensionPreferences.isEnabled else { return }
        NotificationCenter.default.post(name: .toggleBrowserPanel, object: projectID)
    }

    func createCommandTab(projectID: UUID, title: String, command: String) {
        dispatch(.createCommandTab(projectID: projectID, areaID: nil, title: title, command: command))
    }

    func createStartupCommandTab(projectID: UUID, title: String, command: String, seed: CodingAgentSessionSeed? = nil) {
        dispatch(.createStartupCommandTab(StartupCommandTabRequest(
            projectID: projectID,
            areaID: nil,
            title: title,
            command: command,
            seed: seed
        )))
    }

    func createCommandSplit(projectID: UUID, title: String, command: String) {
        dispatch(.createCommandSplit(projectID: projectID, title: title, command: command))
    }

    func openFile(_ filePath: String, projectID: UUID) {
        let settings = EditorSettings.shared
        if settings.defaultEditor == .terminalCommand {
            let command = settings.externalEditorCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !command.isEmpty {
                openFileInExternalEditor(filePath, projectID: projectID, command: command)
                return
            }
        }
        for workspaceTab in workspaceTabs(for: projectID) where workspaceTab.root.allAreas().contains(where: { area in
            area.tabs.contains(where: { $0.content.editorState?.filePath == filePath })
        }) {
            activateWorkspaceTab(workspaceTab.id, projectID: projectID)
            return
        }
        dispatch(.createEditorTab(projectID: projectID, areaID: nil, filePath: filePath))
    }

    func handleFileMoved(from oldPath: String, to newPath: String) {
        guard oldPath != newPath else { return }
        let oldPrefix = oldPath + "/"
        for workspace in workspaces.values {
            for workspaceTab in workspace.tabs {
                for area in workspaceTab.root.allAreas() {
                    for tab in area.tabs {
                        guard let editorState = tab.content.editorState else { continue }
                        let currentPath = editorState.filePath
                        if currentPath == oldPath {
                            editorState.updateFilePath(newPath)
                        } else if currentPath.hasPrefix(oldPrefix) {
                            editorState.updateFilePath(newPath + "/" + String(currentPath.dropFirst(oldPrefix.count)))
                        }
                    }
                }
            }
        }
    }

    func openDiffViewer(vcs: VCSTabState, filePath: String, isStaged: Bool, projectID: UUID) {
        for workspaceTab in workspaceTabs(for: projectID) where workspaceTab.root.allAreas().contains(where: { area in
            area.tabs.contains(where: { tab in
                guard let diff = tab.content.diffViewerState else { return false }
                return diff.filePath == filePath && diff.isStaged == isStaged
            })
        }) {
            activateWorkspaceTab(workspaceTab.id, projectID: projectID)
            return
        }
        dispatch(.createDiffViewerTab(
            projectID: projectID,
            areaID: nil,
            request: DiffViewerRequest(vcs: vcs, filePath: filePath, isStaged: isStaged)
        ))
    }

    private func openFileInExternalEditor(_ filePath: String, projectID: UUID, command: String) {
        for workspaceTab in workspaceTabs(for: projectID) where workspaceTab.root.allAreas().contains(where: { area in
            area.tabs.contains(where: { $0.content.pane?.externalEditorFilePath == filePath })
        }) {
            activateWorkspaceTab(workspaceTab.id, projectID: projectID)
            return
        }
        dispatch(.createExternalEditorTab(projectID: projectID, areaID: nil, filePath: filePath, command: command))
    }

    func closeTab(_ tabID: UUID, projectID: UUID) {
        guard let area = focusedArea(for: projectID) else { return }
        closeTab(tabID, areaID: area.id, projectID: projectID)
    }

    func closeTab(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        if needsUnsavedEditorConfirmation(tabID: tabID, areaID: areaID, projectID: projectID) {
            pendingUnsavedEditorTabClose = PendingTabClose(projectID: projectID, areaID: areaID, tabID: tabID)
            return
        }
        if needsProcessConfirmation(tabID: tabID, areaID: areaID, projectID: projectID) {
            pendingProcessTabClose = PendingTabClose(projectID: projectID, areaID: areaID, tabID: tabID)
            return
        }
        closeTabWithLastCheck(tabID, areaID: areaID, projectID: projectID)
    }

    func forceCloseTab(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        clearPendingProcessCloseIfMatching(tabID: tabID, areaID: areaID, projectID: projectID)
        unpinTabIfNeeded(tabID, areaID: areaID, projectID: projectID)
        dispatch(.closeTab(projectID: projectID, areaID: areaID, tabID: tabID))
    }

    func closeMonitoredTerminal(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        guard let workspace = workspace(for: projectID),
              let workspaceTab = workspace.tabs.first(where: { $0.root.findArea(id: areaID) != nil }),
              let area = workspaceTab.root.findArea(id: areaID)
        else { return }

        if area.tabs.count > 1 {
            guard let removed = area.removeTab(tabID) else { return }
            if let paneID = removed.content.pane?.id {
                AIActivityStore.shared.stop(paneID: paneID)
                CodingAgentSessionMetadataStore.shared.remove(paneID: paneID)
                terminalViews.removeView(for: paneID)
            }
            reconcilePendingClosures()
            pruneNavigationHistory()
            recordCurrentNavigationEntry()
            if let activeTabID = NotificationNavigator.activeTabID(appState: self) {
                NotificationStore.shared.markAsRead(tabID: activeTabID)
            }
            saveWorkspaces()
            saveSelection()
            return
        }

        if workspaceTab.root.allAreas().count > 1 {
            dispatch(.closeArea(projectID: projectID, areaID: areaID))
            return
        }

        forceCloseTab(workspaceTab.id, areaID: areaID, projectID: projectID)
    }

    func confirmCloseRunningTab() {
        guard let pending = pendingProcessTabClose else { return }
        pendingProcessTabClose = nil
        closeTabWithLastCheck(pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
    }

    func cancelCloseRunningTab() {
        pendingProcessTabClose = nil
    }

    func confirmCloseUnsavedEditorTab() {
        guard let pending = pendingUnsavedEditorTabClose else { return }
        pendingUnsavedEditorTabClose = nil
        closeTabWithLastCheck(pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
    }

    func saveAndCloseUnsavedEditorTab() {
        guard let pending = pendingUnsavedEditorTabClose else { return }
        guard let key = activeWorktreeKey(for: pending.projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: pending.areaID),
              let tab = area.tabs.first(where: { $0.id == pending.tabID }),
              let editorState = tab.content.editorState
        else {
            pendingUnsavedEditorTabClose = nil
            return
        }
        pendingUnsavedEditorTabClose = nil
        let fileName = editorState.fileName
        Task { [weak self] in
            do {
                try await editorState.saveFileAsync()
                self?.closeTabWithLastCheck(pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
            } catch {
                self?.pendingSaveErrorMessage = "Failed to save \(fileName): \(error.localizedDescription)"
            }
        }
    }

    func cancelCloseUnsavedEditorTab() {
        pendingUnsavedEditorTabClose = nil
    }

    private func closeTabWithLastCheck(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        if !ProjectLifecyclePreferences.keepOpenWhenNoTabs,
           isLastTabInProject(tabID, areaID: areaID, projectID: projectID)
        {
            pendingLastTabClose = PendingTabClose(projectID: projectID, areaID: areaID, tabID: tabID)
            return
        }
        dispatch(.closeTab(projectID: projectID, areaID: areaID, tabID: tabID))
    }

    func confirmCloseLastTab() {
        guard let pending = pendingLastTabClose else { return }
        pendingLastTabClose = nil
        dispatch(.closeTab(projectID: pending.projectID, areaID: pending.areaID, tabID: pending.tabID))
    }

    func cancelCloseLastTab() {
        pendingLastTabClose = nil
    }

    private func unpinTabIfNeeded(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        _ = areaID
        guard let workspace = workspace(for: projectID),
              let tab = workspace.tabs.first(where: { $0.id == tabID }),
              tab.isPinned
        else { return }
        workspace.togglePin(tabID)
    }

    private func isLastTabInProject(_ tabID: UUID, areaID: UUID, projectID: UUID) -> Bool {
        _ = tabID
        _ = areaID
        return workspaceTabs(for: projectID).count <= 1
    }

    func unsavedEditorTabs() -> [EditorTabState] {
        var result: [EditorTabState] = []
        for workspace in workspaces.values {
            for workspaceTab in workspace.tabs {
                for area in workspaceTab.root.allAreas() {
                    for tab in area.tabs {
                        if let state = tab.content.editorState, state.isModified {
                            result.append(state)
                        }
                    }
                }
            }
        }
        return result
    }

    private func needsUnsavedEditorConfirmation(tabID: UUID, areaID: UUID, projectID: UUID) -> Bool {
        _ = areaID
        guard let workspace = workspace(for: projectID),
              let tab = workspace.tabs.first(where: { $0.id == tabID })
        else { return false }
        return tab.root.allAreas().contains(where: { area in
            area.tabs.contains(where: { $0.content.editorState?.isModified == true })
        })
    }

    private func needsProcessConfirmation(tabID: UUID, areaID: UUID, projectID: UUID) -> Bool {
        guard TabCloseConfirmationPreferences.confirmRunningProcess else { return false }
        _ = areaID
        guard let workspace = workspace(for: projectID),
              let tab = workspace.tabs.first(where: { $0.id == tabID })
        else { return false }
        let paneIDs = tab.root.allAreas().flatMap { area in area.tabs.compactMap { $0.content.pane?.id } }
        return paneIDs.contains { terminalViews.needsConfirmQuit(for: $0) }
    }

    func selectTabByIndex(_ index: Int, projectID: UUID) {
        dispatch(.selectTabByIndex(projectID: projectID, areaID: nil, index: index))
    }

    func selectNextTab(projectID: UUID) {
        dispatch(.selectNextTab(projectID: projectID))
    }

    func selectPreviousTab(projectID: UUID) {
        dispatch(.selectPreviousTab(projectID: projectID))
    }

    func activeTab(for projectID: UUID) -> TerminalTab? {
        activeWorkspaceTab(for: projectID)?.activeContent
    }

    func togglePinActiveTab(projectID: UUID) {
        guard let workspace = workspace(for: projectID),
              let tabID = workspace.activeTabID
        else { return }
        workspace.togglePin(tabID)
        saveWorkspaces()
    }

    func dispatch(_ action: Action) {
        if case let .focusArea(projectID, areaID) = action,
           let key = activeWorktreeKey(for: projectID),
           focusedAreaID[key] == areaID
        {
            return
        }

        if case let .selectTab(projectID, areaID, tabID) = action,
           let key = activeWorktreeKey(for: projectID),
           let workspace = workspaces[key],
           workspace.activeTabID == tabID
        {
            _ = areaID
            return
        }

        let currentWorkspaceRootSignature = workspaceRootSignature(workspaceRoots)
        var workspace = WorkspaceState(
            activeProjectID: activeProjectID,
            activeWorktreeID: activeWorktreeID,
            activeWorktreePath: activeWorktreePath,
            workspaces: workspaces,
            workspaceRoots: workspaceRoots,
            focusedAreaID: focusedAreaID,
            focusHistory: focusHistory,
            keepProjectOpenWhenEmpty: ProjectLifecyclePreferences.keepOpenWhenNoTabs
        )
        let effects = WorkspaceReducer.reduce(action: action, state: &workspace)
        if activeProjectID != workspace.activeProjectID {
            activeProjectID = workspace.activeProjectID
        }
        if activeWorktreeID != workspace.activeWorktreeID {
            activeWorktreeID = workspace.activeWorktreeID
        }
        if activeWorktreePath != workspace.activeWorktreePath {
            activeWorktreePath = workspace.activeWorktreePath
        }
        workspaces = workspace.workspaces
        if currentWorkspaceRootSignature != workspaceRootSignature(workspace.workspaceRoots) {
            workspaceRoots = workspace.workspaceRoots
        }
        if focusedAreaID != workspace.focusedAreaID {
            focusedAreaID = workspace.focusedAreaID
        }
        if focusHistory != workspace.focusHistory {
            focusHistory = workspace.focusHistory
        }
        reconcilePendingClosures()

        for paneID in effects.paneIDsToRemove {
            AIActivityStore.shared.stop(paneID: paneID)
            CodingAgentSessionMetadataStore.shared.remove(paneID: paneID)
            terminalViews.removeView(for: paneID)
        }

        if !effects.projectIDsToRemove.isEmpty {
            onProjectsEmptied?(effects.projectIDsToRemove)
        }

        pruneNavigationHistory()
        recordCurrentNavigationEntry()

        if let activeTabID = NotificationNavigator.activeTabID(appState: self) {
            NotificationStore.shared.markAsRead(tabID: activeTabID)
        }

        saveWorkspaces()
        saveSelection()
    }

    func goBack() {
        step(delta: -1)
    }

    func goForward() {
        step(delta: 1)
    }

    private func step(delta: Int) {
        while true {
            let targetIndex = navigation.cursor + delta
            guard targetIndex >= 0, targetIndex < navigation.entries.count else { return }
            let target = navigation.entries[targetIndex]
            if applyNavigationEntry(target) {
                navigation.setCursor(targetIndex)
                return
            }
            navigation.removeEntry(at: targetIndex)
        }
    }

    private func applyNavigationEntry(_ entry: NavigationEntry) -> Bool {
        guard navigationEntryIsLive(entry) else { return false }
        navigation.performWithRecordingSuppressed {
            dispatch(.navigate(
                projectID: entry.projectID,
                worktreeID: entry.worktreeID,
                areaID: entry.areaID,
                tabID: entry.tabID
            ))
        }
        return true
    }

    private func currentNavigationEntry() -> NavigationEntry? {
        guard let projectID = activeProjectID,
              let worktreeID = activeWorktreeID[projectID]
        else { return nil }
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        guard let root = workspaceRoots[key],
              let areaID = focusedAreaID[key],
              let area = root.findArea(id: areaID)
        else { return nil }
        return NavigationEntry(
            projectID: projectID,
            worktreeID: worktreeID,
            areaID: areaID,
            tabID: area.activeTabID
        )
    }

    private func recordCurrentNavigationEntry() {
        guard let entry = currentNavigationEntry() else { return }
        navigation.record(entry)
    }

    private func pruneNavigationHistory() {
        let originalCount = navigation.entries.count
        navigation.removeEntries { !navigationEntryIsLive($0) }
        guard navigation.entries.count != originalCount else { return }
        guard let live = currentNavigationEntry(),
              let matchIndex = navigation.entries.lastIndex(of: live)
        else { return }
        navigation.setCursor(matchIndex)
    }

    private func navigationEntryIsLive(_ entry: NavigationEntry) -> Bool {
        let key = WorktreeKey(projectID: entry.projectID, worktreeID: entry.worktreeID)
        guard let workspace = workspaces[key]
        else { return false }
        for tab in workspace.tabs {
            guard let area = tab.root.findArea(id: entry.areaID) else { continue }
            if let tabID = entry.tabID, !area.tabs.contains(where: { $0.id == tabID }) {
                continue
            }
            return true
        }
        return false
    }

    private func workspaceRootSignature(_ roots: [WorktreeKey: SplitNode]) -> [WorktreeKey: UUID] {
        roots.mapValues(\.id)
    }

    private func resolvedWorktreePath(
        projectID: UUID,
        worktreeID: UUID,
        worktrees: [UUID: [Worktree]]
    ) -> String? {
        if let path = worktrees[projectID]?.first(where: { $0.id == worktreeID })?.path {
            return path
        }
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        if let workspace = workspaces[key], let tab = workspace.tabs.first {
            return tab.projectPath
        }
        if let root = workspaceRoots[key], case let .tabArea(area) = root {
            return area.projectPath
        }
        return workspaceRoots[key]?.allAreas().first?.projectPath
    }

    private func clearPendingProcessCloseIfMatching(tabID: UUID, areaID: UUID, projectID: UUID) {
        guard let pending = pendingProcessTabClose else { return }
        guard pending.projectID == projectID,
              pending.areaID == areaID,
              pending.tabID == tabID
        else { return }
        pendingProcessTabClose = nil
    }

    private func reconcilePendingClosures() {
        if let pending = pendingLastTabClose,
           !tabExists(tabID: pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
        {
            pendingLastTabClose = nil
        }

        if let pending = pendingUnsavedEditorTabClose,
           !tabExists(tabID: pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
        {
            pendingUnsavedEditorTabClose = nil
        }

        if let pending = pendingProcessTabClose,
           !tabExists(tabID: pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
        {
            pendingProcessTabClose = nil
        }
    }

    private func tabExists(tabID: UUID, areaID: UUID, projectID: UUID) -> Bool {
        guard let workspace = workspace(for: projectID),
              let tab = workspace.tabs.first(where: { $0.id == tabID })
        else { return false }
        return tab.root.findArea(id: areaID) != nil
    }

    private func activateWorkspaceTab(_ workspaceTabID: UUID, projectID: UUID) {
        dispatch(.selectTab(projectID: projectID, areaID: UUID(), tabID: workspaceTabID))
    }

    private func refreshWorkspaceMirrors() {
        workspaceRoots = [:]
        focusedAreaID = [:]
        focusHistory = [:]
        for (key, workspace) in workspaces {
            guard let tab = workspace.activeTab else { continue }
            workspaceRoots[key] = tab.root
            focusedAreaID[key] = tab.focusedAreaID
            focusHistory[key] = tab.focusHistory
        }
    }

    func focusArea(_ areaID: UUID, projectID: UUID) {
        dispatch(.focusArea(projectID: projectID, areaID: areaID))
    }

    func focusPaneLeft(projectID: UUID) {
        dispatch(.focusPaneLeft(projectID: projectID))
    }

    func focusPaneRight(projectID: UUID) {
        dispatch(.focusPaneRight(projectID: projectID))
    }

    func focusPaneUp(projectID: UUID) {
        dispatch(.focusPaneUp(projectID: projectID))
    }

    func focusPaneDown(projectID: UUID) {
        dispatch(.focusPaneDown(projectID: projectID))
    }

    func selectProjectByIndex(_ index: Int, projects: [Project], worktrees: [UUID: [Worktree]]) {
        guard index >= 0, index < projects.count else { return }
        let project = projects[index]
        let list = worktrees[project.id] ?? []
        guard let target = list.first(where: { $0.isPrimary }) ?? list.first else { return }
        selectProject(project, worktree: target)
    }

    func selectNextProject(projects: [Project], worktrees: [UUID: [Worktree]]) {
        dispatch(.selectNextProject(projects: projects, worktrees: worktrees))
    }

    func selectPreviousProject(projects: [Project], worktrees: [UUID: [Worktree]]) {
        dispatch(.selectPreviousProject(projects: projects, worktrees: worktrees))
    }

    func removeProject(_ projectID: UUID) {
        dispatch(.removeProject(projectID: projectID))
    }

    func removeWorktree(projectID: UUID, worktree: Worktree, replacement: Worktree?) {
        guard !worktree.isPrimary else { return }
        dispatch(.removeWorktree(
            projectID: projectID,
            worktreeID: worktree.id,
            replacementWorktreeID: replacement?.id,
            replacementWorktreePath: replacement?.path
        ))
    }
}

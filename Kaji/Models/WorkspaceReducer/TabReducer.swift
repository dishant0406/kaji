import Foundation

@MainActor
enum TabReducer {
    static func createTab(projectID: UUID, areaID _: UUID?, state: inout WorkspaceState) {
        _ = appendWorkspaceTab(projectID: projectID, state: &state) { path in
            let area = TabArea(projectPath: path)
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func createTabInDirectory(
        projectID: UUID,
        areaID _: UUID?,
        directory: String,
        state: inout WorkspaceState
    ) {
        _ = appendWorkspaceTab(projectID: projectID, state: &state) { _ in
            let area = TabArea(
                projectPath: directory,
                existingTab: TerminalTab(pane: TerminalPaneState(projectPath: directory))
            )
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func createVCSTab(projectID: UUID, areaID _: UUID?, state: inout WorkspaceState) {
        _ = appendWorkspaceTab(projectID: projectID, state: &state) { path in
            let area = TabArea(projectPath: path, existingTab: TerminalTab(vcsState: VCSTabState(projectPath: path)))
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func createParentAgentTab(
        projectID: UUID,
        areaID _: UUID?,
        agentID: UUID? = nil,
        initialSessionPath: String? = nil,
        state: inout WorkspaceState
    ) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let path = WorkspaceReducerShared.activeProjectPath(projectID: projectID, state: state)
        else { return }
        let workspace = state.workspaces[key] ?? WorktreeWorkspace()
        let area = TabArea(
            projectPath: path,
            existingTab: TerminalTab(parentAgentState: ParentAgentTabState(
                id: agentID ?? UUID(),
                projectID: projectID,
                worktreeID: key.worktreeID,
                projectPath: path,
                initialSessionPath: initialSessionPath
            ))
        )
        let tab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        workspace.appendTab(tab)
        state.workspaces[key] = workspace
        WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
    }

    static func createCommandTab(
        projectID: UUID,
        areaID _: UUID?,
        title: String,
        command: String,
        state: inout WorkspaceState
    ) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = appendWorkspaceTab(projectID: projectID, state: &state) { path in
            let area = TabArea(projectPath: path, existingTab: TerminalTab(pane: TerminalPaneState(
                projectPath: path,
                title: title,
                injectedCommand: trimmed
            )))
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func createStartupCommandTab(_ request: AppState.StartupCommandTabRequest, state: inout WorkspaceState) {
        let trimmed = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || request.injectedCommand != nil else { return }
        _ = appendWorkspaceTab(projectID: request.projectID, state: &state) { path in
            let area = TabArea(projectPath: path, existingTab: TerminalTab(pane: TerminalPaneState(
                projectPath: path,
                title: request.title,
                startupCommand: trimmed.isEmpty ? nil : trimmed,
                injectedCommand: request.injectedCommand,
                agentSessionSeed: request.seed
            )))
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func createCommandSplit(
        projectID: UUID,
        title: String,
        command: String,
        state: inout WorkspaceState
    ) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let root = state.workspaceRoots[key],
              let area = WorkspaceReducerShared.resolveArea(key: key, areaID: nil, state: state)
        else {
            createCommandTab(projectID: projectID, areaID: nil, title: title, command: trimmed, state: &state)
            return
        }

        let content = TerminalTab(pane: TerminalPaneState(
            projectPath: area.projectPath,
            title: title,
            injectedCommand: trimmed
        ))
        let (newRoot, newAreaID) = root.splittingWithTab(
            areaID: area.id,
            direction: .horizontal,
            position: .second,
            tab: content
        )
        state.workspaceRoots[key] = newRoot
        guard let newAreaID else { return }
        FocusReducer.focusArea(newAreaID, key: key, state: &state)
        state.workspaces[key]?.activeTab?.root = newRoot
        state.workspaces[key]?.activeTab?.focusedAreaID = newAreaID
    }

    static func createBrowserSplit(projectID: UUID, state: inout WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let path = WorkspaceReducerShared.activeProjectPath(projectID: projectID, state: state)
        else { return }
        let browser = TerminalTab(browserState: BrowserPaneState(projectPath: path))
        guard let root = state.workspaceRoots[key],
              let area = WorkspaceReducerShared.resolveArea(key: key, areaID: nil, state: state)
        else {
            let tabArea = TabArea(projectPath: path, existingTab: browser)
            let tab = WorkspaceTab(root: .tabArea(tabArea), focusedAreaID: tabArea.id)
            let workspace = state.workspaces[key] ?? WorktreeWorkspace()
            workspace.appendTab(tab)
            state.workspaces[key] = workspace
            WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
            return
        }
        let (newRoot, newAreaID) = root.splittingWithTab(
            areaID: area.id,
            direction: .horizontal,
            position: .second,
            tab: browser
        )
        state.workspaceRoots[key] = newRoot
        guard let newAreaID else { return }
        FocusReducer.focusArea(newAreaID, key: key, state: &state)
        state.workspaces[key]?.activeTab?.root = newRoot
        state.workspaces[key]?.activeTab?.focusedAreaID = newAreaID
    }

    static func createParentAgentSplit(projectID: UUID, state: inout WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let path = WorkspaceReducerShared.activeProjectPath(projectID: projectID, state: state)
        else { return }
        let agent = TerminalTab(parentAgentState: ParentAgentTabState(
            projectID: projectID,
            worktreeID: key.worktreeID,
            projectPath: path
        ))
        guard let root = state.workspaceRoots[key],
              let area = WorkspaceReducerShared.resolveArea(key: key, areaID: nil, state: state)
        else {
            let tabArea = TabArea(projectPath: path, existingTab: agent)
            let tab = WorkspaceTab(root: .tabArea(tabArea), focusedAreaID: tabArea.id)
            let workspace = state.workspaces[key] ?? WorktreeWorkspace()
            workspace.appendTab(tab)
            state.workspaces[key] = workspace
            WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
            return
        }
        let (newRoot, newAreaID) = root.splittingWithTab(
            areaID: area.id,
            direction: .horizontal,
            position: .second,
            tab: agent
        )
        state.workspaceRoots[key] = newRoot
        guard let newAreaID else { return }
        FocusReducer.focusArea(newAreaID, key: key, state: &state)
        state.workspaces[key]?.activeTab?.root = newRoot
        state.workspaces[key]?.activeTab?.focusedAreaID = newAreaID
    }

    static func createEditorTab(projectID: UUID, areaID _: UUID?, filePath: String, state: inout WorkspaceState) {
        DebugFileLog.log("EditorTab", "createEditorTab projectID=\(projectID.uuidString) path=\(filePath)")
        _ = appendWorkspaceTab(projectID: projectID, state: &state) { path in
            let area = TabArea(projectPath: path, existingTab: TerminalTab(editorState: EditorTabState(
                projectPath: path,
                filePath: filePath
            )))
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func createFilePreviewTab(
        projectID: UUID,
        areaID _: UUID?,
        filePath: String,
        kind: FilePreviewKind,
        state: inout WorkspaceState
    ) {
        DebugFileLog.log("FilePreviewTab", "createFilePreviewTab projectID=\(projectID.uuidString) path=\(filePath)")
        _ = appendWorkspaceTab(projectID: projectID, state: &state) { path in
            let area = TabArea(projectPath: path, existingTab: TerminalTab(filePreviewState: FilePreviewTabState(
                projectPath: path,
                filePath: filePath,
                kind: kind
            )))
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func createExternalEditorTab(
        projectID: UUID,
        areaID _: UUID?,
        filePath: String,
        command: String,
        state: inout WorkspaceState
    ) {
        _ = appendWorkspaceTab(projectID: projectID, state: &state) { path in
            let pane = TerminalPaneState(
                projectPath: path,
                title: "\(TabArea.commandTitle(command)) \(URL(fileURLWithPath: filePath).lastPathComponent)",
                startupCommand: TabArea.editorLaunchCommand(command: command, filePath: filePath),
                externalEditorFilePath: filePath
            )
            let area = TabArea(projectPath: path, existingTab: TerminalTab(pane: pane))
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func createDiffViewerTab(
        projectID: UUID,
        areaID _: UUID?,
        request: AppState.DiffViewerRequest,
        state: inout WorkspaceState
    ) {
        _ = appendWorkspaceTab(projectID: projectID, state: &state) { path in
            let vcs = VCSTabState(projectPath: path, files: request.files, diffSource: request.source)
            let area = TabArea(projectPath: path, existingTab: TerminalTab(diffViewerState: DiffViewerTabState(
                vcs: vcs,
                filePath: request.filePath,
                isStaged: request.isStaged,
                files: request.files
            )))
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func createProblemsTab(projectID: UUID, areaID _: UUID?, state: inout WorkspaceState) {
        _ = appendWorkspaceTab(projectID: projectID, state: &state) { path in
            let area = TabArea(projectPath: path, existingTab: TerminalTab(problemsState: ProblemsTabState(projectPath: path)))
            return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        }
    }

    static func selectTab(projectID: UUID, areaID _: UUID?, tabID: UUID, state: inout WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let workspace = state.workspaces[key]
        else { return }
        workspace.selectTab(tabID)
        WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
    }

    static func selectTabByIndex(projectID: UUID, areaID _: UUID?, index: Int, state: inout WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let workspace = state.workspaces[key]
        else { return }
        workspace.selectTabByIndex(index)
        WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
    }

    static func selectNextTab(projectID: UUID, state: inout WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let workspace = state.workspaces[key]
        else { return }
        workspace.selectNextTab()
        WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
    }

    static func selectPreviousTab(projectID: UUID, state: inout WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let workspace = state.workspaces[key]
        else { return }
        workspace.selectPreviousTab()
        WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
    }

    static func closeTab(
        _ tabID: UUID,
        areaID _: UUID,
        key: WorktreeKey,
        state: inout WorkspaceState,
        effects: inout WorkspaceSideEffects
    ) {
        guard let workspace = state.workspaces[key],
              let tab = workspace.removeTab(tabID)
        else { return }

        let paneIDs = tab.root.allAreas().flatMap { area in
            area.tabs.compactMap { $0.content.pane?.id }
        }
        effects.paneIDsToRemove.append(contentsOf: paneIDs)

        guard !workspace.tabs.isEmpty else {
            WorkspaceReducerShared.clearWorkspace(key: key, state: &state)
            WorkspaceReducerShared.handleProjectEmptiedIfNeeded(
                projectID: key.projectID,
                state: &state,
                effects: &effects
            )
            return
        }

        WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
    }

    private static func appendWorkspaceTab(
        projectID: UUID,
        state: inout WorkspaceState,
        makeTab: (String) -> WorkspaceTab
    ) -> WorkspaceTab? {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let path = WorkspaceReducerShared.activeProjectPath(projectID: projectID, state: state)
        else { return nil }
        let workspace = state.workspaces[key] ?? WorktreeWorkspace()
        let tab = makeTab(path)
        workspace.appendTab(tab)
        state.workspaces[key] = workspace
        WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
        return tab
    }
}

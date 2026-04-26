import Foundation

@MainActor
enum TabReducer {
    static func createTab(projectID: UUID, areaID: UUID?, state: inout WorkspaceState) {
        guard let (key, area, created) = WorkspaceReducerShared.resolveOrCreateFocusedArea(
            projectID: projectID,
            areaID: areaID,
            state: &state,
            createArea: { TabArea(projectPath: $0) }
        )
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        if !created {
            area.createTab()
        }
    }

    static func createTabInDirectory(
        projectID: UUID,
        areaID: UUID?,
        directory: String,
        state: inout WorkspaceState
    ) {
        guard let (key, area, created) = WorkspaceReducerShared.resolveOrCreateFocusedArea(
            projectID: projectID,
            areaID: areaID,
            state: &state,
            createArea: { path in
                TabArea(
                    projectPath: path,
                    existingTab: TerminalTab(pane: TerminalPaneState(projectPath: directory))
                )
            }
        )
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        if !created {
            area.createTab(inDirectory: directory)
        }
    }

    static func createVCSTab(projectID: UUID, areaID: UUID?, state: inout WorkspaceState) {
        guard let (key, area, created) = WorkspaceReducerShared.resolveOrCreateFocusedArea(
            projectID: projectID,
            areaID: areaID,
            state: &state,
            createArea: { path in
                TabArea(
                    projectPath: path,
                    existingTab: TerminalTab(vcsState: VCSTabState(projectPath: path))
                )
            }
        )
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        if !created {
            area.createVCSTab()
        }
    }

    static func createCommandTab(
        projectID: UUID,
        areaID: UUID?,
        title: String,
        command: String,
        state: inout WorkspaceState
    ) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let (key, area, created) = WorkspaceReducerShared.resolveOrCreateFocusedArea(
            projectID: projectID,
            areaID: areaID,
            state: &state,
            createArea: { path in
                TabArea(
                    projectPath: path,
                    existingTab: TerminalTab(pane: TerminalPaneState(
                        projectPath: path,
                        title: title,
                        injectedCommand: trimmed
                    ))
                )
            }
        )
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        if !created {
            area.createCommandTab(title: title, command: trimmed)
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
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state) else { return }
        guard let root = state.workspaceRoots[key],
              let area = WorkspaceReducerShared.resolveArea(key: key, areaID: nil, state: state)
        else {
            createCommandTab(
                projectID: projectID,
                areaID: nil,
                title: title,
                command: trimmed,
                state: &state
            )
            return
        }

        let tab = TerminalTab(pane: TerminalPaneState(
            projectPath: area.projectPath,
            title: title,
            injectedCommand: trimmed
        ))
        let (newRoot, newAreaID) = root.splittingWithTab(
            areaID: area.id,
            direction: .horizontal,
            position: .second,
            tab: tab
        )
        state.workspaceRoots[key] = newRoot
        guard let newAreaID else { return }
        FocusReducer.focusArea(newAreaID, key: key, state: &state)
    }

    static func createEditorTab(projectID: UUID, areaID: UUID?, filePath: String, state: inout WorkspaceState) {
        guard let (key, area, created) = WorkspaceReducerShared.resolveOrCreateFocusedArea(
            projectID: projectID,
            areaID: areaID,
            state: &state,
            createArea: { path in
                TabArea(
                    projectPath: path,
                    existingTab: TerminalTab(editorState: EditorTabState(
                        projectPath: path,
                        filePath: filePath
                    ))
                )
            }
        )
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        if !created {
            area.createEditorTab(filePath: filePath)
        }
    }

    static func createExternalEditorTab(
        projectID: UUID,
        areaID: UUID?,
        filePath: String,
        command: String,
        state: inout WorkspaceState
    ) {
        guard let (key, area, created) = WorkspaceReducerShared.resolveOrCreateFocusedArea(
            projectID: projectID,
            areaID: areaID,
            state: &state,
            createArea: { path in
                let title = "\(TabArea.commandTitle(command)) \(URL(fileURLWithPath: filePath).lastPathComponent)"
                let pane = TerminalPaneState(
                    projectPath: path,
                    title: title,
                    startupCommand: TabArea.editorLaunchCommand(command: command, filePath: filePath),
                    externalEditorFilePath: filePath
                )
                return TabArea(projectPath: path, existingTab: TerminalTab(pane: pane))
            }
        )
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        if !created {
            area.createExternalEditorTab(filePath: filePath, command: command)
        }
    }

    static func createDiffViewerTab(
        projectID: UUID,
        areaID: UUID?,
        request: AppState.DiffViewerRequest,
        state: inout WorkspaceState
    ) {
        guard let (key, area, created) = WorkspaceReducerShared.resolveOrCreateFocusedArea(
            projectID: projectID,
            areaID: areaID,
            state: &state,
            createArea: { path in
                let vcs = VCSTabState(projectPath: path)
                return TabArea(projectPath: path, existingTab: TerminalTab(diffViewerState: DiffViewerTabState(
                    vcs: vcs,
                    filePath: request.filePath,
                    isStaged: request.isStaged
                )))
            }
        )
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        if !created {
            area.createDiffViewerTab(
                vcs: request.vcs,
                filePath: request.filePath,
                isStaged: request.isStaged
            )
        }
    }

    static func selectTab(projectID: UUID, areaID: UUID?, tabID: UUID, state: inout WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let area = WorkspaceReducerShared.resolveArea(key: key, areaID: areaID, state: state)
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        area.selectTab(tabID)
    }

    static func selectTabByIndex(projectID: UUID, areaID: UUID?, index: Int, state: inout WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let area = WorkspaceReducerShared.resolveArea(key: key, areaID: areaID, state: state)
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        area.selectTabByIndex(index)
    }

    static func selectNextTab(projectID: UUID, state: WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let area = WorkspaceReducerShared.resolveArea(key: key, areaID: nil, state: state)
        else { return }
        area.selectNextTab()
    }

    static func selectPreviousTab(projectID: UUID, state: WorkspaceState) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let area = WorkspaceReducerShared.resolveArea(key: key, areaID: nil, state: state)
        else { return }
        area.selectPreviousTab()
    }

    static func closeTab(
        _ tabID: UUID,
        areaID: UUID,
        key: WorktreeKey,
        state: inout WorkspaceState,
        effects: inout WorkspaceSideEffects
    ) {
        guard let root = state.workspaceRoots[key],
              let area = root.findArea(id: areaID)
        else { return }

        let areaCount = root.allAreas().count
        if area.tabs.count <= 1, areaCount > 1 {
            SplitReducer.closeArea(areaID, key: key, state: &state, effects: &effects)
            return
        }

        if let paneID = area.closeTab(tabID) {
            effects.paneIDsToRemove.append(paneID)
        }

        guard area.tabs.isEmpty else { return }
        WorkspaceReducerShared.clearWorkspace(key: key, state: &state)
        WorkspaceReducerShared.handleProjectEmptiedIfNeeded(
            projectID: key.projectID,
            state: &state,
            effects: &effects
        )
    }
}

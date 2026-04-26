import SwiftUI

struct TerminalArea: View {
    let project: Project
    let worktreeKey: WorktreeKey
    let isActiveProject: Bool
    @Environment(AppState.self) private var appState
    @Environment(TabDragCoordinator.self) private var dragCoordinator

    private var root: SplitNode? {
        appState.workspaceRoots[worktreeKey]
    }

    private var focusedAreaID: UUID? {
        appState.focusedAreaID[worktreeKey]
    }

    private var rootIsTabArea: Bool {
        guard let root else { return false }
        if case .tabArea = root { return true }
        return false
    }

    var body: some View {
        if let root {
            VStack(spacing: 0) {
                PaneNode(
                    node: root,
                    focusedAreaID: focusedAreaID,
                    isActiveProject: isActiveProject,
                    showTabStrip: !rootIsTabArea,
                    showVCSButton: false,
                    projectID: project.id,
                    onFocusArea: { areaID in
                        appState.dispatch(.focusArea(projectID: project.id, areaID: areaID))
                    },
                    onSelectTab: { areaID, tabID in
                        appState.dispatch(.selectTab(projectID: project.id, areaID: areaID, tabID: tabID))
                    },
                    onCreateTab: { areaID in
                        appState.dispatch(.createTab(projectID: project.id, areaID: areaID))
                    },
                    onCreateVCSTab: { areaID in
                        _ = areaID
                        NotificationCenter.default.post(name: .toggleAttachedVCS, object: project.id)
                    },
                    onCloseTab: { areaID, tabID in
                        appState.closeTab(tabID, areaID: areaID, projectID: project.id)
                    },
                    onForceCloseTab: { areaID, tabID in
                        appState.forceCloseTab(tabID, areaID: areaID, projectID: project.id)
                    },
                    onSplit: { areaID, dir in
                        appState.dispatch(.splitArea(.init(
                            projectID: project.id,
                            areaID: areaID,
                            direction: dir,
                            position: .second
                        )))
                    },
                    onCloseArea: { areaID in
                        appState.dispatch(.closeArea(projectID: project.id, areaID: areaID))
                    },
                    onDropAction: { result in
                        appState.dispatch(result.action(projectID: project.id))
                    }
                )

                if isActiveProject {
                    CLILauncherFooter(projectID: project.id)
                }
            }
            .environment(\.activeWorktreeKey, worktreeKey)
            .onPreferenceChange(AreaFramePreferenceKey.self) { frames in
                guard isActiveProject, dragCoordinator.activeDrag != nil else { return }
                dragCoordinator.setAreaFrames(frames, forProject: project.id)
            }
        }
    }
}

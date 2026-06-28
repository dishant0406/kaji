import SwiftUI

struct TerminalArea: View {
    let project: Project
    let worktreeKey: WorktreeKey
    let isActiveProject: Bool
    @Environment(AppState.self) private var appState
    @Environment(TabDragCoordinator.self) private var dragCoordinator
    @Environment(PaneReorderCoordinator.self) private var paneReorderCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var root: SplitNode? {
        appState.workspaceRoots[worktreeKey]
    }

    private var focusedAreaID: UUID? {
        appState.focusedAreaID[worktreeKey]
    }

    var body: some View {
        if let root {
            let showsPaneHeader = root.allAreas().count > 1
            VStack(spacing: 0) {
                PaneNode(
                    node: root,
                    focusedAreaID: focusedAreaID,
                    isActiveProject: isActiveProject,
                    showTabStrip: false,
                    showPaneHeader: showsPaneHeader,
                    showVCSButton: false,
                    projectID: project.id,
                    onFocusArea: { areaID in
                        appState.dispatch(.focusArea(projectID: project.id, areaID: areaID))
                    },
                    onSelectTab: { areaID, tabID in
                        appState.dispatch(.selectTab(projectID: project.id, areaID: areaID, tabID: tabID))
                    },
                    onCreateTab: { areaID in
                        withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
                            appState.dispatch(.createTab(projectID: project.id, areaID: areaID))
                        }
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
                        withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
                            appState.dispatch(.splitArea(.init(
                                projectID: project.id,
                                areaID: areaID,
                                direction: dir,
                                position: .second
                            )))
                        }
                    },
                    onCloseArea: { areaID in
                        withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
                            appState.dispatch(.closeArea(projectID: project.id, areaID: areaID))
                        }
                    },
                    onDropAction: { result in
                        withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
                            appState.dispatch(result.action(projectID: project.id))
                        }
                    },
                    onMoveArea: { result in
                        withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
                            appState.dispatch(result.action(projectID: project.id))
                        }
                    }
                )
            }
            .environment(\.activeWorktreeKey, worktreeKey)
            .onPreferenceChange(PaneAreaFramePreferenceKey.self) { frames in
                guard isActiveProject else { return }
                paneReorderCoordinator.setAreaFrames(frames, forProject: project.id)
            }
            .onPreferenceChange(AreaFramePreferenceKey.self) { frames in
                guard isActiveProject else { return }
                if dragCoordinator.activeDrag != nil {
                    dragCoordinator.setAreaFrames(frames, forProject: project.id)
                }
            }
            .onPreferenceChange(TabStripFramePreferenceKey.self) { frames in
                guard isActiveProject, dragCoordinator.activeDrag != nil else { return }
                dragCoordinator.setStripFrames(frames, forProject: project.id)
            }
        }
    }
}

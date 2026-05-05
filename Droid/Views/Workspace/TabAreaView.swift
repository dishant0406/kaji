import SwiftUI

struct TabAreaView: View {
    let area: TabArea
    let isFocused: Bool
    let isActiveProject: Bool
    let showTabStrip: Bool
    let showPaneHeader: Bool
    let showVCSButton: Bool
    let projectID: UUID
    let onFocus: () -> Void
    let onSelectTab: (UUID) -> Void
    let onCreateTab: () -> Void
    let onCreateVCSTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onForceCloseTab: (UUID) -> Void
    let onSplit: (SplitDirection) -> Void
    let onCloseArea: () -> Void
    let onDropAction: (TabDragCoordinator.DropResult) -> Void
    let onMoveArea: (PaneDragCoordinator.DropResult) -> Void
    @Environment(TabDragCoordinator.self) private var dragCoordinator
    @Environment(PaneDragCoordinator.self) private var paneDragCoordinator
    @Environment(AppState.self) private var appState
    @Environment(\.workspaceOccluded) private var workspaceOccluded
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if showPaneHeader {
                PaneHeaderView(
                    title: PaneHeaderTitle.resolve(for: area),
                    isFocused: isFocused,
                    isDragging: paneDragCoordinator.activeDrag?.sourceAreaID == area.id,
                    onClose: onCloseArea,
                    onDragChanged: handlePaneDragChanged,
                    onDragEnded: handlePaneDragEnded
                )
                Rectangle().fill(DroidTheme.border).frame(height: 1)
            }
            if showTabStrip {
                PaneTabStrip(
                    areaID: area.id,
                    tabs: PaneTabStrip.snapshots(from: area.tabs),
                    activeTabID: area.activeTabID,
                    isFocused: isFocused,
                    showVCSButton: showVCSButton,
                    projectID: projectID,
                    onSelectTab: onSelectTab,
                    onCreateTab: onCreateTab,
                    onCreateVCSTab: onCreateVCSTab,
                    onCloseTab: onCloseTab,
                    onSplit: onSplit,
                    onDropAction: onDropAction,
                    onCreateTabAdjacent: { tabID, side in
                        area.createTabAdjacent(to: tabID, side: side)
                    },
                    onTogglePin: { tabID in
                        area.togglePin(tabID)
                    },
                    onSetCustomTitle: { tabID, title in
                        area.setCustomTitle(tabID, title: title)
                        appState.saveWorkspaces()
                    },
                    onSetColorID: { tabID, colorID in
                        area.setColorID(tabID, colorID: colorID)
                        appState.saveWorkspaces()
                    },
                    onReorderTab: { fromOffsets, toOffset in
                        area.reorderTab(fromOffsets: fromOffsets, toOffset: toOffset)
                    }
                )
                Rectangle().fill(DroidTheme.border).frame(height: 1)
            }
            ZStack {
                ForEach(area.tabs) { tab in
                    let isActive = tab.id == area.activeTabID
                    TabContentView(
                        tab: tab,
                        focused: isActive && isFocused && isActiveProject,
                        visible: isActive && isActiveProject && !workspaceOccluded,
                        onFocus: onFocus,
                        onProcessExit: { onForceCloseTab(tab.id) },
                        onSplitRequest: { direction, position in
                            appState.dispatch(.splitArea(.init(
                                projectID: projectID,
                                areaID: area.id,
                                direction: direction,
                                position: position
                            )))
                        }
                    )
                    .zIndex(isActive ? 1 : 0)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                }
            }
            .overlay {
                DropZoneHighlight(
                    zone: paneDragCoordinator.hoveredZone ?? .left,
                    showsTabStripTarget: false
                )
                .opacity(
                    paneDragCoordinator.activeDrag != nil &&
                        paneDragCoordinator.hoveredAreaID == area.id &&
                        paneDragCoordinator.hoveredZone != nil ? 1 : 0
                )
                .animation(DroidMotion.preferred(DroidMotion.fast, reduceMotion: reduceMotion), value: paneDragCoordinator.hoveredAreaID)
                .animation(DroidMotion.preferred(DroidMotion.fast, reduceMotion: reduceMotion), value: paneDragCoordinator.hoveredZone)
            }
        }
        .background {
            if paneDragCoordinator.activeDrag != nil {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: AreaFramePreferenceKey.self,
                        value: [area.id: geo.frame(in: .named(DragCoordinateSpace.mainWindow))]
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInTerminal)) { _ in
            guard isFocused, isActiveProject else { return }
            guard let tabID = area.activeTabID,
                  let tab = area.tabs.first(where: { $0.id == tabID })
            else { return }
            guard let pane = tab.content.pane else { return }
            TerminalViewRegistry.shared.existingView(for: pane.id)?.startSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveActiveEditor)) { _ in
            guard isFocused, isActiveProject else { return }
            guard let tabID = area.activeTabID,
                  let tab = area.tabs.first(where: { $0.id == tabID })
            else { return }
            guard let editorState = tab.content.editorState else { return }
            Task { @MainActor in
                do {
                    try await editorState.saveFileAsync()
                } catch {
                    appState.pendingSaveErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handlePaneDragChanged(_ value: DragGesture.Value) {
        if paneDragCoordinator.activeDrag == nil {
            paneDragCoordinator.beginDrag(sourceAreaID: area.id, projectID: projectID)
        }
        paneDragCoordinator.updatePosition(value.location)
    }

    private func handlePaneDragEnded(_ value: DragGesture.Value) {
        paneDragCoordinator.updatePosition(value.location)
        if let result = paneDragCoordinator.endDrag() {
            onMoveArea(result)
        }
    }
}

private struct TabContentView: View {
    let tab: TerminalTab
    let focused: Bool
    let visible: Bool
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onSplitRequest: (SplitDirection, SplitPosition) -> Void

    var body: some View {
        switch tab.content {
        case let .terminal(pane):
            TerminalPane(
                state: pane,
                focused: focused,
                visible: visible,
                onFocus: onFocus,
                onProcessExit: onProcessExit,
                onSplitRequest: onSplitRequest
            )
        case let .vcs(vcsState):
            VCSTabView(state: vcsState, focused: focused, onFocus: onFocus)
        case let .editor(editorState):
            EditorPane(state: editorState, focused: focused, onFocus: onFocus)
        case let .diffViewer(diffState):
            DiffViewerPane(state: diffState, focused: focused, onFocus: onFocus)
        case .parentAgent:
            ParentAgentTabContent()
        }
    }
}

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
    let onTerminalProcessExit: (UUID) -> Void
    let onSplit: (SplitDirection) -> Void
    let onCloseArea: () -> Void
    let onDropAction: (TabDragCoordinator.DropResult) -> Void
    let onMoveArea: (PaneReorderCoordinator.DropResult) -> Void
    @Environment(TabDragCoordinator.self) private var dragCoordinator
    @Environment(PaneReorderCoordinator.self) private var paneReorderCoordinator
    @Environment(AppState.self) private var appState
    @Environment(\.workspaceOccluded) private var workspaceOccluded
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if showPaneHeader {
                PaneHeaderView(
                    title: PaneHeaderTitle.resolve(for: area),
                    isFocused: isFocused,
                    isDragging: paneReorderCoordinator.activeDrag?.sourceAreaID == area.id,
                    onClose: onCloseArea,
                    onDragChanged: handlePaneDragChanged,
                    onDragEnded: handlePaneDragEnded
                )
                Rectangle().fill(KajiTheme.border).frame(height: 1)
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
                Rectangle().fill(KajiTheme.border).frame(height: 1)
            }
            ZStack {
                ForEach(area.mountedNonEditorTabs) { tab in
                    let isActive = tab.id == area.activeTabID
                    TabContentView(
                        tab: tab,
                        focused: isActive && isFocused && isActiveProject,
                        visible: isActive && isActiveProject && !workspaceOccluded,
                        onFocus: onFocus,
                        onProcessExit: { onTerminalProcessExit(tab.id) },
                        onClosePane: onCloseArea,
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
                if let editorTab = area.hostedEditorTab {
                    let isActive = editorTab.id == area.activeTabID
                    EditorAreaHostView(
                        tab: editorTab,
                        focused: isActive && isFocused && isActiveProject,
                        onFocus: onFocus
                    )
                    .zIndex(isActive ? 1 : 0)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                }
            }
            .background(KajiTheme.bg)
            .overlay {
                DropZoneHighlight(
                    zone: paneReorderCoordinator.hoveredZone ?? .left,
                    showsTabStripTarget: false
                )
                .opacity(
                    paneReorderCoordinator.activeDrag != nil &&
                        paneReorderCoordinator.hoveredAreaID == area.id &&
                        paneReorderCoordinator.hoveredZone != nil ? 1 : 0
                )
                .animation(KajiMotion.preferred(KajiMotion.fast, reduceMotion: reduceMotion), value: paneReorderCoordinator.hoveredAreaID)
                .animation(KajiMotion.preferred(KajiMotion.fast, reduceMotion: reduceMotion), value: paneReorderCoordinator.hoveredZone)
            }
        }
        .background {
            PaneAreaWindowFramePreferenceView(areaID: area.id)

            if dragCoordinator.activeDrag != nil {
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

    private func handlePaneDragChanged(_ position: CGPoint) {
        if paneReorderCoordinator.activeDrag == nil {
            paneReorderCoordinator.beginReorder(sourceAreaID: area.id, projectID: projectID)
        }
        paneReorderCoordinator.updatePosition(position)
    }

    private func handlePaneDragEnded(_ position: CGPoint) {
        paneReorderCoordinator.updatePosition(position)
        if let result = paneReorderCoordinator.endReorder() {
            onMoveArea(result)
        }
    }
}

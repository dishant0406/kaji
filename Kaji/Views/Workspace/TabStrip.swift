import SwiftUI

struct PaneTabStrip: View {
    struct TabSnapshot: Identifiable {
        let id: UUID
        let title: String
        let kind: TerminalTab.Kind
        let isPinned: Bool
        let hasCustomTitle: Bool
        let colorID: String?
    }

    let areaID: UUID
    let tabs: [TabSnapshot]
    let activeTabID: UUID?
    let isFocused: Bool
    var isWindowTitleBar: Bool = false
    var showVCSButton = true
    var showSettingsButton = true
    let projectID: UUID
    let onSelectTab: (UUID) -> Void
    let onCreateTab: () -> Void
    let onCreateVCSTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSplit: (SplitDirection) -> Void
    let onDropAction: (TabDragCoordinator.DropResult) -> Void
    let onCreateTabAdjacent: (UUID, TabArea.InsertSide) -> Void
    let onTogglePin: (UUID) -> Void
    let onSetCustomTitle: (UUID, String?) -> Void
    let onSetColorID: (UUID, String?) -> Void
    let onReorderTab: (IndexSet, Int) -> Void
    @Environment(TabDragCoordinator.self) private var dragCoordinator
    @State private var notificationStore = NotificationStore.shared
    @State private var dragState = TabDragState()
    private let addButtonWidth: CGFloat = 30

    static func snapshots(from tabs: [TerminalTab]) -> [TabSnapshot] {
        tabs.map { tab in
            TabSnapshot(
                id: tab.id,
                title: tab.title,
                kind: tab.kind,
                isPinned: tab.isPinned,
                hasCustomTitle: tab.customTitle != nil,
                colorID: tab.colorID
            )
        }
    }

    static func workspaceSnapshots(from tabs: [WorkspaceTab]) -> [TabSnapshot] {
        tabs.map { tab in
            TabSnapshot(
                id: tab.id,
                title: tab.title,
                kind: tab.kind,
                isPinned: tab.isPinned,
                hasCustomTitle: tab.hasCustomTitle,
                colorID: tab.colorID
            )
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    tabRow(availableWidth: geo.size.width)
                        .frame(minWidth: geo.size.width, alignment: .leading)
                        .background(WindowDragRepresentable(alwaysEnabled: isWindowTitleBar))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)

            if showsTrailingActions {
                HStack(spacing: 0) {
                    if isWindowTitleBar, let version = UpdateService.shared.availableUpdateVersion {
                        UpdateBadge(version: version) {
                            UpdateService.shared.checkForUpdates()
                        }
                        .padding(.trailing, 4)
                    }
                    if showVCSButton {
                        IconButton(symbol: "magnifyingglass", size: 12, accessibilityLabel: "Quick Open") {
                            NotificationCenter.default.post(name: .quickOpen, object: nil)
                        }
                        .help(shortcutTooltip("Quick Open", for: .quickOpen))
                        FileDiffIconButton(action: onCreateVCSTab)
                            .help(shortcutTooltip("Source Control", for: .openVCSTab))
                        FileTreeIconButton {
                            NotificationCenter.default.post(name: .toggleFileTree, object: nil)
                        }
                        .help(shortcutTooltip("File Tree", for: .toggleFileTree))
                    }
                    if showSettingsButton {
                        IconButton(symbol: "gearshape", accessibilityLabel: "Settings") {
                            NotificationCenter.default.post(name: .toggleSettings, object: nil)
                        }
                        .help("Settings (⌘,)")
                    }
                }
                .padding(.trailing, 8)
                .fixedSize(horizontal: true, vertical: false)
                .background(WindowDragRepresentable(alwaysEnabled: isWindowTitleBar))
            }
        }
        .frame(height: 36)
        .background {
            if dragCoordinator.activeDrag != nil {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: TabStripFramePreferenceKey.self,
                        value: [areaID: geo.frame(in: .named(DragCoordinateSpace.mainWindow))]
                    )
                }
            }
        }
        .onPreferenceChange(TabFramePreferenceKey.self) { frames in
            guard dragState.draggedID != nil else { return }
            dragState.frames = frames
        }
    }

    private func tabRow(availableWidth: CGFloat) -> some View {
        let count = max(tabs.count, 1)
        let effectiveWidth = availableWidth > 0
            ? max(0, availableWidth - trailingTabButtonWidth - 6)
            : TabCell.maxWidth * CGFloat(count)
        let perTabIdeal = effectiveWidth / CGFloat(count)
        let perTabWidth = max(TabCell.minWidth, min(TabCell.maxWidth, perTabIdeal))

        return HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                TabCell(
                    tab: tab,
                    active: tab.id == activeTabID,
                    paneFocused: isFocused,
                    hasUnread: notificationStore.hasUnread(tabID: tab.id),
                    isAnyDragging: dragState.draggedID != nil,
                    shortcutIndex: index < 9 ? index + 1 : nil,
                    onSelect: { onSelectTab(tab.id) },
                    onClose: { onCloseTab(tab.id) },
                    onCreateLeft: { onCreateTabAdjacent(tab.id, .left) },
                    onCreateRight: { onCreateTabAdjacent(tab.id, .right) },
                    onTogglePin: { onTogglePin(tab.id) },
                    onSetCustomTitle: { onSetCustomTitle(tab.id, $0) },
                    onSetColorID: { onSetColorID(tab.id, $0) }
                )
                .frame(width: perTabWidth)
                .background {
                    if dragState.draggedID != nil {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: TabFramePreferenceKey.self,
                                value: [tab.id: geo.frame(in: .named(DragCoordinateSpace.mainWindow))]
                            )
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(DragCoordinateSpace.mainWindow))
                        .onChanged { value in
                            handleDragChanged(
                                tab: tab,
                                globalLocation: value.location,
                                dragStartGlobalLocation: value.startLocation
                            )
                        }
                        .onEnded { value in
                            handleDragEnded(
                                tab: tab,
                                globalLocation: value.location,
                                dragStartGlobalLocation: value.startLocation
                            )
                        }
                )
            }

            TabAddButton(action: onCreateTab)
                .frame(width: addButtonWidth, height: 36, alignment: .center)
        }
    }

    private var trailingTabButtonWidth: CGFloat {
        addButtonWidth
    }

    private var showsTrailingActions: Bool {
        showVCSButton || showSettingsButton || (isWindowTitleBar && UpdateService.shared.availableUpdateVersion != nil)
    }

    private func shortcutTooltip(_ name: String, for action: ShortcutAction) -> String {
        "\(name) (\(KeyBindingStore.shared.combo(for: action).displayString))"
    }

    private static let dragActivationDistance: CGFloat = 4

    private func handleDragChanged(
        tab: TabSnapshot,
        globalLocation: CGPoint,
        dragStartGlobalLocation: CGPoint
    ) {
        if !dragState.didSelect {
            dragState.didSelect = true
            onSelectTab(tab.id)
        }

        let dx = globalLocation.x - dragStartGlobalLocation.x
        let dy = globalLocation.y - dragStartGlobalLocation.y
        let distance = (dx * dx + dy * dy).squareRoot()

        if dragState.draggedID == nil {
            guard distance >= Self.dragActivationDistance else { return }
            dragState.draggedID = tab.id
            dragState.lastReorderTargetID = nil
            dragCoordinator.beginDrag(tabID: tab.id, sourceAreaID: areaID, projectID: projectID)
        }

        dragCoordinator.updatePosition(globalLocation)
        reorderIfNeeded(at: globalLocation)
    }

    private func handleDragEnded(
        tab: TabSnapshot,
        globalLocation: CGPoint,
        dragStartGlobalLocation: CGPoint
    ) {
        if !dragState.didSelect {
            onSelectTab(tab.id)
        }
        if let result = dragCoordinator.endDrag() {
            onDropAction(result)
        }
        dragState.draggedID = nil
        dragState.frames = [:]
        dragState.lastReorderTargetID = nil
        dragState.didSelect = false
    }

    private func reorderIfNeeded(at location: CGPoint) {
        guard let draggedID = dragState.draggedID else { return }
        guard dragCoordinator.hoveredAreaID == areaID, dragCoordinator.hoveredZone == .center else {
            dragState.lastReorderTargetID = nil
            return
        }
        var hoveredTargetID: UUID?

        for (id, frame) in dragState.frames where id != draggedID {
            guard frame.contains(location) else { continue }
            hoveredTargetID = id
            guard dragState.lastReorderTargetID != id else { return }

            guard let sourceIndex = tabs.firstIndex(where: { $0.id == draggedID }),
                  let destIndex = tabs.firstIndex(where: { $0.id == id })
            else { return }

            dragState.lastReorderTargetID = id
            let offset = destIndex > sourceIndex ? destIndex + 1 : destIndex
            onReorderTab(IndexSet(integer: sourceIndex), offset)
            return
        }

        if hoveredTargetID == nil {
            dragState.lastReorderTargetID = nil
        }
    }
}

private struct TabDragState {
    var draggedID: UUID?
    var frames: [UUID: CGRect] = [:]
    var lastReorderTargetID: UUID?
    var didSelect = false
}

private struct TabAddButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(hovered ? KajiTheme.surface : KajiTheme.bg)
                KajiIcon(systemName: "plus", size: 11)
                    .foregroundStyle(hovered ? KajiTheme.fg : KajiTheme.fgMuted)
            }
            .frame(width: 30, height: 36)
            .overlay {
                Rectangle()
                    .strokeBorder(KajiTheme.border.opacity(hovered ? 0.75 : 0.35), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .kajiPointer()
        .help("New Tab (\(KeyBindingStore.shared.combo(for: .newTab).displayString))")
        .accessibilityLabel("New Tab")
    }
}

private typealias TabFramePreferenceKey = UUIDFramePreferenceKey<TabFrameTag>

private struct TabWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TabCell: View {
    static let minWidth: CGFloat = 56
    static let maxWidth: CGFloat = 200
    static let titleHideThreshold: CGFloat = 96

    let tab: PaneTabStrip.TabSnapshot
    let active: Bool
    let paneFocused: Bool
    var hasUnread: Bool = false
    var isAnyDragging: Bool = false
    var shortcutIndex: Int?
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCreateLeft: () -> Void
    let onCreateRight: () -> Void
    let onTogglePin: () -> Void
    let onSetCustomTitle: (String?) -> Void
    let onSetColorID: (String?) -> Void
    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showColorPicker = false
    @State private var measuredWidth: CGFloat = TabCell.maxWidth
    @FocusState private var renameFieldFocused: Bool

    private var titleHidden: Bool {
        measuredWidth < Self.titleHideThreshold
    }

    private var tabColor: Color? {
        ProjectIconColor.color(for: tab.colorID)
    }

    private var tabBackground: Color {
        if let tabColor {
            let opacity = if active { 0.14 } else if hovered { 0.08 } else { 0.02 }
            return tabColor.opacity(opacity)
        }
        if active { return KajiTheme.surface }
        if hovered { return KajiTheme.hover }
        return KajiTheme.bg
    }

    private var bottomAccentColor: Color? {
        guard active, paneFocused else { return nil }
        return tabColor ?? KajiTheme.accent
    }

    private var showBadge: Bool {
        guard let shortcutIndex,
              let action = ShortcutAction.tabAction(for: shortcutIndex)
        else { return false }
        return ModifierKeyMonitor.shared.isHolding(
            modifiers: KeyBindingStore.shared.combo(for: action).modifiers
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                tabIconView
                    .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
                    .opacity(titleHidden && hovered && !tab.isPinned ? 0 : 1)
                    .overlay(alignment: .topTrailing) {
                        if hasUnread, !active {
                            Circle()
                                .fill(KajiTheme.accent)
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -3)
                        }
                    }

                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fg)
                        .focused($renameFieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                } else if !titleHidden {
                    Text(tab.title)
                        .kajiFont(size: 12)
                        .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.leading, titleHidden ? 0 : 12)
            .padding(.trailing, titleHidden ? 0 : 32)
            .frame(maxWidth: .infinity, alignment: titleHidden ? .center : .leading)
            .frame(height: 36)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: TabWidthPreferenceKey.self, value: geo.size.width)
                }
            }
            .onPreferenceChange(TabWidthPreferenceKey.self) { measuredWidth = $0 }
            .overlay(alignment: titleHidden ? .center : .trailing) {
                if !tab.isPinned {
                    let visible = titleHidden ? hovered : (active || hovered)
                    KajiIcon(systemName: "xmark", size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                        .padding(.trailing, titleHidden ? 0 : 10)
                        .opacity(visible ? 1 : 0)
                        .onTapGesture(perform: onClose)
                        .kajiPointer()
                        .accessibilityLabel("Close Tab")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .overlay {
                if showBadge, let shortcutIndex,
                   let action = ShortcutAction.tabAction(for: shortcutIndex)
                {
                    ShortcutBadge(label: KeyBindingStore.shared.combo(for: action).displayString)
                }
            }
            .overlay(alignment: .bottom) {
                if let accentColor = bottomAccentColor {
                    Rectangle()
                        .fill(accentColor)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
            .background(tabBackground)
            .overlay {
                Rectangle()
                    .strokeBorder(KajiTheme.border.opacity(active || hovered ? 0.75 : 0.35), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                guard !isAnyDragging else { return }
                hovered = hovering
            }
            .onChange(of: isAnyDragging) { _, dragging in
                if dragging { hovered = false }
            }
            .kajiPointer()
            .overlay {
                if !tab.isPinned {
                    MiddleClickView(action: onClose)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tabAccessibilityLabel)
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityAddTraits(.isButton)
            .contextMenu {
                Button("New Tab to the Left") { onCreateLeft() }
                Button("New Tab to the Right") { onCreateRight() }
                Divider()
                Button("Rename Tab") { startRename() }
                if tab.hasCustomTitle {
                    Button("Reset Title") { onSetCustomTitle(nil) }
                }
                Button("Set Tab Color…") { showColorPicker = true }
                if tab.colorID != nil {
                    Button("Reset Tab Color") { onSetColorID(nil) }
                }
                Divider()
                Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                    onTogglePin()
                }
                if !tab.isPinned {
                    Divider()
                    Button("Close Tab") { onClose() }
                }
            }
            .kajiPopover(isPresented: $showColorPicker, preferredEdge: .bottom) {
                ProjectIconColorPicker(title: "Tab Color", selectedID: tab.colorID) { id in
                    onSetColorID(id)
                    showColorPicker = false
                }
            }

            Rectangle().fill(KajiTheme.border.opacity(0.55)).frame(width: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .renameActiveTab)) { _ in
            guard active else { return }
            startRename()
        }
    }

    private func startRename() {
        renameText = tab.title
        isRenaming = true
        renameFieldFocused = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        onSetCustomTitle(trimmed.isEmpty ? nil : trimmed)
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }

    private var tabAccessibilityLabel: String {
        var label = tab.title
        switch tab.kind {
        case .terminal: label += ", Terminal"
        case .vcs: label += ", Source Control"
        case .editor: label += ", Editor"
        case .diffViewer: label += ", Diff Viewer"
        case .parentAgent: label += ", Kaji Agent"
        case .codeGraph: label += ", Code Graph"
        case .browser: label += ", Browser"
        }
        if tab.isPinned { label += ", Pinned" }
        if hasUnread { label += ", Unread" }
        return label
    }

    @ViewBuilder
    private var tabIconView: some View {
        if tab.isPinned {
            KajiIcon(systemName: "pin.fill", size: 10)
        } else if tab.kind == .vcs {
            KajiIcon(systemName: "file.diff", size: 12)
        } else if tab.kind == .editor {
            KajiIcon(systemName: "pencil.line", size: 12)
        } else if tab.kind == .diffViewer {
            KajiIcon(systemName: "rectangle.split.2x1", size: 11)
        } else if tab.kind == .parentAgent {
            KajiIcon(systemName: "sparkles", size: 12)
        } else if tab.kind == .codeGraph {
            KajiIcon(systemName: "point.3.connected.trianglepath.dotted", size: 12)
        } else if tab.kind == .browser {
            KajiIcon(systemName: "globe", size: 12)
        } else {
            KajiIcon(systemName: "terminal", size: 12)
        }
    }
}

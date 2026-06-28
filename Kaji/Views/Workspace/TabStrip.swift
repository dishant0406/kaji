import Reorderable
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
    var allowsExternalDrops = true
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
    @State private var isReordering = false
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
                .autoScrollOnEdges()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)

            if showsTrailingActions {
                HStack(spacing: 0) {
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
        .background(tabStripFrameReader)
    }

    private func tabRow(availableWidth: CGFloat) -> some View {
        let count = max(tabs.count, 1)
        let effectiveWidth = availableWidth > 0
            ? max(0, availableWidth - trailingTabButtonWidth - 6)
            : TabCell.maxWidth * CGFloat(count)
        let perTabIdeal = effectiveWidth / CGFloat(count)
        let perTabWidth = max(TabCell.minWidth, min(TabCell.maxWidth, perTabIdeal))

        return HStack(spacing: 0) {
            ReorderableHStack(
                Self.indexedSnapshots(from: tabs),
                onMove: { source, destination in
                    onReorderTab(
                        IndexSet(integer: source),
                        ReorderMoveDestination.arrayMoveOffset(from: source, to: destination)
                    )
                },
                onDragStateChange: { dragging in
                    isReordering = dragging
                },
                externalCoordinateSpaceName: DragCoordinateSpace.mainWindow,
                onExternalDragChanged: { item, value in
                    handleExternalDragChanged(tab: item.tab, value: value)
                },
                onExternalDragEnded: { item, value in
                    handleExternalDragEnded(tab: item.tab, value: value)
                },
                content: { item, isDragged in
                    let tab = item.tab
                    TabCell(
                        tab: tab,
                        active: tab.id == activeTabID,
                        paneFocused: isFocused,
                        hasUnread: notificationStore.hasUnread(tabID: tab.id),
                        isAnyDragging: isReordering,
                        shortcut: item.shortcut,
                        onSelect: { onSelectTab(tab.id) },
                        onClose: { onCloseTab(tab.id) },
                        onCreateLeft: { onCreateTabAdjacent(tab.id, .left) },
                        onCreateRight: { onCreateTabAdjacent(tab.id, .right) },
                        onTogglePin: { onTogglePin(tab.id) },
                        onSetCustomTitle: { onSetCustomTitle(tab.id, $0) },
                        onSetColorID: { onSetColorID(tab.id, $0) }
                    )
                    .frame(width: perTabWidth)
                    .opacity(isDragged ? 0.92 : 1)
                    .scaleEffect(isDragged ? 1.015 : 1)
                    .animation(KajiMotion.select, value: isDragged)
                }
            )

            TabAddButton(action: onCreateTab)
                .frame(width: addButtonWidth, height: 36, alignment: .center)
        }
    }

    private var trailingTabButtonWidth: CGFloat {
        addButtonWidth
    }

    private var showsTrailingActions: Bool {
        showVCSButton || showSettingsButton
    }

    private func shortcutTooltip(_ name: String, for action: ShortcutAction) -> String {
        "\(name) (\(KeyBindingStore.shared.combo(for: action).displayString))"
    }

    private var tabStripFrameReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: TabStripFramePreferenceKey.self,
                value: [areaID: geo.frame(in: .named(DragCoordinateSpace.mainWindow))]
            )
        }
    }

    private func handleExternalDragChanged(tab: TabSnapshot, value: DragGesture.Value) {
        guard allowsExternalDrops else { return }
        if dragCoordinator.activeDrag == nil {
            dragCoordinator.beginDrag(tabID: tab.id, sourceAreaID: areaID, projectID: projectID)
        }
        dragCoordinator.updatePosition(value.location)
    }

    private func handleExternalDragEnded(tab _: TabSnapshot, value: DragGesture.Value) {
        guard allowsExternalDrops else {
            dragCoordinator.cancelDrag()
            return
        }
        dragCoordinator.updatePosition(value.location)
        if let result = dragCoordinator.endDrag() {
            onDropAction(result)
        }
    }
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
        .kajiHoverEffect(isActive: hovered, scale: 1.04)
        .kajiChangeFeedback(KajiMotion.tapFeedback, value: hovered, isEnabled: hovered)
        .kajiPointer()
        .help("New Tab (\(KeyBindingStore.shared.combo(for: .newTab).displayString))")
        .accessibilityLabel("New Tab")
    }
}

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
    var shortcut: PaneTabStrip.TabShortcutSnapshot?
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
        guard let shortcut else { return false }
        return ModifierKeyMonitor.shared.isHolding(modifiers: shortcut.modifiers)
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
                if showBadge, let shortcut {
                    ShortcutBadge(label: shortcut.displayString)
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
            .onTapGesture {
                guard !isAnyDragging else { return }
                onSelect()
            }
            .onHover { hovering in
                guard !isAnyDragging else { return }
                hovered = hovering
            }
            .onChange(of: isAnyDragging) { _, dragging in
                if dragging { hovered = false }
            }
            .animation(KajiMotion.fast, value: active)
            .animation(KajiMotion.hover, value: hovered)
            .kajiChangeFeedback(KajiMotion.selectionFeedback, value: active, isEnabled: active)
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
        case .filePreview: label += ", File Preview"
        case .diffViewer: label += ", Diff Viewer"
        case .problems: label += ", Problems"
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
        } else if tab.kind == .filePreview {
            KajiIcon(systemName: "eye", size: 12)
        } else if tab.kind == .diffViewer {
            KajiIcon(systemName: "rectangle.split.2x1", size: 11)
        } else if tab.kind == .problems {
            KajiIcon(systemName: "exclamationmark.triangle", size: 12)
        } else if tab.kind == .parentAgent {
            KajiLogo(size: 12)
        } else if tab.kind == .codeGraph {
            KajiIcon(systemName: "point.3.connected.trianglepath.dotted", size: 12)
        } else if tab.kind == .browser {
            KajiIcon(systemName: "globe", size: 12)
        } else {
            KajiIcon(systemName: "terminal", size: 12)
        }
    }
}

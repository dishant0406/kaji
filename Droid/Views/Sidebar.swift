import SwiftUI

enum SidebarLayout {
    static let collapsedWidth: CGFloat = 52
    static let expandedWidth: CGFloat = 248
    static let width: CGFloat = collapsedWidth

    static func resolvedWidth(expanded: Bool) -> CGFloat {
        expanded ? expandedWidth : collapsedWidth
    }
}

struct Sidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var sidebarTransparencyEnabled = false
    @AppStorage(AppearanceSettingsKeys.interfaceTransparencyAmount) private var interfaceTransparencyAmount = 0.7
    @State private var dragState = ProjectDragState()
    @State private var expanded = UserDefaults.standard.bool(forKey: "droid.sidebarExpanded")
    @Binding var showAIUsagePopover: Bool

    var body: some View {
        VStack(spacing: 0) {
            projectList
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()

            SidebarFooter(
                expanded: expanded,
                showAIUsagePopover: $showAIUsagePopover
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .frame(width: SidebarLayout.resolvedWidth(expanded: expanded))
        .background(
            SidebarBackgroundSurface(
                transparencyEnabled: sidebarTransparencyEnabled,
                transparencyAmount: interfaceTransparencyAmount
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            toggleExpanded()
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            expanded.toggle()
        }
        UserDefaults.standard.set(expanded, forKey: "droid.sidebarExpanded")
    }

    private var addButton: some View {
        SidebarAddProjectButton(expanded: expanded) {
            ProjectOpenService.openProject(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        }
        .help(shortcutTooltip("Add Project", for: .openProject))
    }

    private var projectList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: expanded ? 4 : 6) {
                ForEach(Array(projectStore.projects.enumerated()), id: \.element.id) { index, project in
                    Group {
                        if expanded {
                            ExpandedProjectRow(
                                project: project,
                                shortcutIndex: index < 9 ? index + 1 : nil,
                                isAnyDragging: dragState.draggedID != nil,
                                onSelect: { select(project) },
                                onRemove: { remove(project) },
                                onRename: { projectStore.rename(id: project.id, to: $0) },
                                onSetLogo: { projectStore.setLogo(id: project.id, to: $0) },
                                onSetIconColor: { projectStore.setIconColor(id: project.id, to: $0) }
                            )
                        } else {
                            ProjectRow(
                                project: project,
                                shortcutIndex: index < 9 ? index + 1 : nil,
                                isAnyDragging: dragState.draggedID != nil,
                                onSelect: { select(project) },
                                onRemove: { remove(project) },
                                onRename: { projectStore.rename(id: project.id, to: $0) },
                                onSetLogo: { projectStore.setLogo(id: project.id, to: $0) },
                                onSetIconColor: { projectStore.setIconColor(id: project.id, to: $0) }
                            )
                        }
                    }
                    .background {
                        if dragState.draggedID != nil {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: UUIDFramePreferenceKey<SidebarFrameTag>.self,
                                    value: [project.id: geo.frame(in: .named("sidebar"))]
                                )
                            }
                        }
                    }
                    .gesture(projectDragGesture(for: project))
                }
                addButton
            }
            .padding(.horizontal, expanded ? 10 : 8)
            .padding(.vertical, 6)
            .onPreferenceChange(UUIDFramePreferenceKey<SidebarFrameTag>.self) { frames in
                guard dragState.draggedID != nil else { return }
                dragState.frames = frames
            }
        }
        .coordinateSpace(name: "sidebar")
    }

    private func shortcutTooltip(_ name: String, for action: ShortcutAction) -> String {
        "\(name) (\(KeyBindingStore.shared.combo(for: action).displayString))"
    }

    private func projectDragGesture(for project: Project) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("sidebar"))
            .onChanged { value in
                if dragState.draggedID == nil {
                    dragState.draggedID = project.id
                    dragState.lastReorderTargetID = nil
                }
                reorderIfNeeded(at: value.location)
            }
            .onEnded { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    dragState.draggedID = nil
                    dragState.frames = [:]
                    dragState.lastReorderTargetID = nil
                }
            }
    }

    private func select(_ project: Project) {
        worktreeStore.ensurePrimary(for: project)
        guard let worktree = worktreeStore.preferred(
            for: project.id,
            matching: appState.activeWorktreeID[project.id]
        )
        else { return }
        appState.selectProject(project, worktree: worktree)
    }

    private func remove(_ project: Project) {
        let capturedProject = project
        let knownWorktrees = worktreeStore.list(for: project.id)
        Task.detached {
            await WorktreeStore.cleanupOnDisk(for: capturedProject, knownWorktrees: knownWorktrees)
        }
        appState.removeProject(project.id)
        projectStore.remove(id: project.id)
        worktreeStore.removeProject(project.id)
    }

    private func reorderIfNeeded(at location: CGPoint) {
        guard let draggedID = dragState.draggedID else { return }
        var hoveredTargetID: UUID?

        for (id, frame) in dragState.frames where id != draggedID {
            guard frame.contains(location) else { continue }
            hoveredTargetID = id
            guard dragState.lastReorderTargetID != id else { return }

            guard let sourceIndex = projectStore.projects.firstIndex(where: { $0.id == draggedID }),
                  let destIndex = projectStore.projects.firstIndex(where: { $0.id == id })
            else { return }

            dragState.lastReorderTargetID = id
            let offset = destIndex > sourceIndex ? destIndex + 1 : destIndex
            withAnimation(.easeInOut(duration: 0.15)) {
                projectStore.reorder(
                    fromOffsets: IndexSet(integer: sourceIndex), toOffset: offset
                )
            }
            return
        }

        if hoveredTargetID == nil {
            dragState.lastReorderTargetID = nil
        }
    }
}

private struct ProjectDragState {
    var draggedID: UUID?
    var frames: [UUID: CGRect] = [:]
    var lastReorderTargetID: UUID?
}

struct SidebarFooter: View {
    var expanded: Bool = false
    @Binding var showAIUsagePopover: Bool
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var sidebarTransparencyEnabled = false
    @AppStorage(AppearanceSettingsKeys.interfaceTransparencyAmount) private var interfaceTransparencyAmount = 0.7
    @AppStorage(AIUsageSettingsStore.usageEnabledKey) private var usageEnabled = false
    @AppStorage(AIUsageSettingsStore.usageDisplayModeKey) private var usageDisplayModeRaw = AIUsageSettingsStore.defaultUsageDisplayMode
        .rawValue
    @AppStorage(AIUsageSettingsStore.sidebarPreviewProviderIDKey) private var pinnedPreviewProviderID: String = ""
    @State private var showThemePicker = false
    @State private var showNotifications = false
    @State private var showResourceMonitor = false
    @State private var notificationStore = NotificationStore.shared
    @State private var resourceMonitor = ResourceMonitorService.shared
    private let usageService = AIUsageService.shared

    private var usageDisplayMode: AIUsageDisplayMode {
        AIUsageDisplayMode(rawValue: usageDisplayModeRaw) ?? AIUsageSettingsStore.defaultUsageDisplayMode
    }

    private let usageRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedFooter
            } else {
                collapsedFooter
            }
        }
        .coordinateSpace(name: "sidebar-footer")
        .task {
            await usageService.refreshIfNeeded()
        }
        .onReceive(usageRefreshTimer) { _ in
            Task {
                await usageService.refreshIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleThemePicker)) { _ in
            showThemePicker.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNotificationPanel)) { _ in
            showNotifications.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAIUsage)) { _ in
            guard usageEnabled else { return }
            toggleAIUsagePopover()
        }
        .onChange(of: usageEnabled) { _, enabled in
            if !enabled {
                showAIUsagePopover = false
            }
        }
    }

    private func postToggleSidebar() {
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }

    private var sidebarToggleLabel: String {
        expanded ? "Collapse Sidebar" : "Expand Sidebar"
    }

    private var sidebarToggleIcon: String {
        "sidebar.left"
    }

    private var notificationBellIcon: String {
        notificationStore.unreadCount > 0 ? "bell.badge" : "bell"
    }

    private var previewProviderDisplay: (percent: Int, iconName: String)? {
        guard let selection = usageService.previewSelection(pinnedRawValue: pinnedPreviewProviderID),
              case .available = selection.snapshot.state
        else { return nil }

        let snapshot = selection.snapshot
        let rowPercent = selection.row?.percent
        let usedPercent = max(0, min(100, rowPercent ?? snapshot.rows.compactMap(\.percent).max() ?? 0))
        let displayPercent: Double = switch usageDisplayMode {
        case .used:
            usedPercent
        case .remaining:
            max(0, min(100, 100 - usedPercent))
        }

        return (Int(displayPercent.rounded()), snapshot.providerIconName)
    }

    private var previewProviderPercentLabel: String? {
        guard let display = previewProviderDisplay else { return nil }
        return "\(max(0, min(100, display.percent)))%"
    }

    private var aiUsageButton: some View {
        AIUsagePreviewButton(
            display: previewProviderDisplay,
            percentLabel: previewProviderPercentLabel,
            expanded: expanded,
            onTap: { toggleAIUsagePopover() }
        )
        .droidPopover(isPresented: $showAIUsagePopover, preferredEdge: .top) {
            AIUsagePanel(
                snapshots: AIUsageService.shared.snapshots,
                isRefreshing: AIUsageService.shared.isRefreshing,
                lastRefreshDate: AIUsageService.shared.lastRefreshDate,
                onRefresh: {
                    Task {
                        await AIUsageService.shared.refresh(force: true)
                    }
                }
            )
        }
        .help("AI Usage (\(KeyBindingStore.shared.combo(for: .toggleAIUsage).displayString))")
    }

    private var collapsedFooter: some View {
        VStack(spacing: 6) {
            if usageEnabled {
                aiUsageButton
            }
            IconButton(symbol: "memorychip", accessibilityLabel: "Resource Monitor") { showResourceMonitor.toggle() }
                .help("Resource Monitor")
                .droidPopover(isPresented: $showResourceMonitor, preferredEdge: .top) {
                    ResourceMonitorPanel(
                        projects: resourceMonitor.projects,
                        isRefreshing: resourceMonitor.isRefreshing,
                        onRefresh: { refreshResourceMonitor() },
                        onDismiss: { showResourceMonitor = false }
                    )
                }
            IconButton(symbol: notificationBellIcon, accessibilityLabel: "Notifications") { showNotifications.toggle() }
                .help("Notifications")
                .droidPopover(isPresented: $showNotifications, preferredEdge: .top) {
                    NotificationPanel(onDismiss: { showNotifications = false })
                }
            IconButton(symbol: "paintbrush", accessibilityLabel: "Theme Picker") { showThemePicker.toggle() }
                .help("Theme Picker (\(KeyBindingStore.shared.combo(for: .toggleThemePicker).displayString))")
                .droidPopover(isPresented: $showThemePicker, preferredEdge: .top) {
                    ThemePicker(
                        onRequestCreate: {
                            showThemePicker = false
                            NotificationCenter.default.post(name: .requestCreateThemeModal, object: nil)
                        },
                        onDismiss: { showThemePicker = false }
                    )
                }
            IconButton(symbol: sidebarToggleIcon, accessibilityLabel: sidebarToggleLabel) { postToggleSidebar() }
                .help("\(sidebarToggleLabel) (\(KeyBindingStore.shared.combo(for: .toggleSidebar).displayString))")
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DroidTheme.border)
                .frame(height: 1)
        }
    }

    private var expandedFooter: some View {
        HStack(spacing: 6) {
            IconButton(symbol: sidebarToggleIcon, accessibilityLabel: sidebarToggleLabel) { postToggleSidebar() }
                .help("\(sidebarToggleLabel) (\(KeyBindingStore.shared.combo(for: .toggleSidebar).displayString))")

            Spacer()

            if usageEnabled {
                aiUsageButton
            }
            IconButton(symbol: "memorychip", accessibilityLabel: "Resource Monitor") { showResourceMonitor.toggle() }
                .help("Resource Monitor")
                .droidPopover(isPresented: $showResourceMonitor, preferredEdge: .top) {
                    ResourceMonitorPanel(
                        projects: resourceMonitor.projects,
                        isRefreshing: resourceMonitor.isRefreshing,
                        onRefresh: { refreshResourceMonitor() },
                        onDismiss: { showResourceMonitor = false }
                    )
                }
            IconButton(symbol: notificationBellIcon, accessibilityLabel: "Notifications") { showNotifications.toggle() }
                .help("Notifications")
                .droidPopover(isPresented: $showNotifications, preferredEdge: .top) {
                    NotificationPanel(onDismiss: { showNotifications = false })
                }
            IconButton(symbol: "paintbrush", accessibilityLabel: "Theme Picker") { showThemePicker.toggle() }
                .help("Theme Picker (\(KeyBindingStore.shared.combo(for: .toggleThemePicker).displayString))")
                .droidPopover(isPresented: $showThemePicker, preferredEdge: .top) {
                    ThemePicker(
                        onRequestCreate: {
                            showThemePicker = false
                            NotificationCenter.default.post(name: .requestCreateThemeModal, object: nil)
                        },
                        onDismiss: { showThemePicker = false }
                    )
                }
        }
        .padding(.horizontal, 10)
        .frame(height: DroidLayout.footerBarHeight)
        .background(
            SidebarBackgroundSurface(
                transparencyEnabled: sidebarTransparencyEnabled,
                transparencyAmount: interfaceTransparencyAmount
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DroidTheme.border)
                .frame(height: 1)
        }
    }

    private func refreshUsage() {
        Task {
            await usageService.refresh(force: true)
        }
    }

    private func toggleAIUsagePopover() {
        showAIUsagePopover.toggle()
    }

    private func refreshResourceMonitor() {
        resourceMonitor.refresh(appState: appState, projectStore: projectStore)
    }
}

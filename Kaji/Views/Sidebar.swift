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
    @State private var isReordering = false
    @State private var expanded = UserDefaults.standard.bool(forKey: "kaji.sidebarExpanded")
    let parentAgentSelected: Bool
    let parentAgentEnabled: Bool

    var body: some View {
        VStack(spacing: 0) {
            projectList
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()

            SidebarFooter(expanded: expanded)
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
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            expanded.toggle()
        }
        UserDefaults.standard.set(expanded, forKey: "kaji.sidebarExpanded")
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
                ReorderableVStack(projectStore.projects, onMove: { source, destination in
                    projectStore.reorder(
                        fromOffsets: IndexSet(integer: source),
                        toOffset: destination
                    )
                }, onDragStateChange: { dragging in
                    isReordering = dragging
                }) { project, isDragged in
                    projectRow(project, isDragged: isDragged)
                }
                addButton
                if parentAgentEnabled {
                    parentAgentButton
                }
            }
            .padding(.horizontal, expanded ? 10 : 8)
            .padding(.vertical, 6)
        }
        .coordinateSpace(name: "sidebar")
    }

    @ViewBuilder
    private func projectRow(_ project: Project, isDragged: Bool) -> some View {
        let index = projectStore.projects.firstIndex(where: { $0.id == project.id }) ?? 0
        Group {
            if expanded {
                ExpandedProjectRow(
                    project: project,
                    shortcutIndex: index < 9 ? index + 1 : nil,
                    isAnyDragging: isReordering,
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
                    isAnyDragging: isReordering,
                    onSelect: { select(project) },
                    onRemove: { remove(project) },
                    onRename: { projectStore.rename(id: project.id, to: $0) },
                    onSetLogo: { projectStore.setLogo(id: project.id, to: $0) },
                    onSetIconColor: { projectStore.setIconColor(id: project.id, to: $0) }
                )
            }
        }
        .opacity(isDragged ? 0.92 : 1)
        .padding(.bottom, expanded ? 4 : 6)
    }

    private func shortcutTooltip(_ name: String, for action: ShortcutAction) -> String {
        "\(name) (\(KeyBindingStore.shared.combo(for: action).displayString))"
    }

    private var parentAgentButton: some View {
        ParentAgentTabButton(selected: parentAgentSelected, expanded: expanded) {
            NotificationCenter.default.post(name: .showParentAgentHome, object: nil)
        }
        .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
        .help("Kaji")
    }

    private func select(_ project: Project) {
        appState.hideParentAgentHome()
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

}

struct SidebarFooter: View {
    var expanded: Bool = false
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var sidebarTransparencyEnabled = false
    @AppStorage(AppearanceSettingsKeys.interfaceTransparencyAmount) private var interfaceTransparencyAmount = 0.7
    @State private var showThemePicker = false
    @State private var showNotifications = false
    @State private var showAgents = false
    @State private var runStore = AgentRunStore.shared
    @State private var notificationStore = NotificationStore.shared

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedFooter
            } else {
                collapsedFooter
            }
        }
        .coordinateSpace(name: "sidebar-footer")
        .onReceive(NotificationCenter.default.publisher(for: .toggleThemePicker)) { _ in
            showThemePicker.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNotificationPanel)) { _ in
            showNotifications.toggle()
        }
    }

    private func postToggleSidebar() {
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }

    private var sidebarToggleLabel: String {
        expanded ? "Collapse Sidebar" : "Expand Sidebar"
    }

    private var notificationBellIcon: String {
        notificationStore.unreadCount > 0 ? "bell.badge" : "bell"
    }

    private var agentItems: [AgentMissionControlItem] {
        _ = notificationStore.readStateVersion
        return AgentRunMissionControlSnapshotBuilder.items(
            runs: runStore.runs,
            notifications: notificationStore.notifications,
            projects: projectStore.projects,
            worktrees: worktreeStore.worktrees
        )
    }

    private var agentsButton: some View {
        AgentMissionControlButton(items: agentItems, expanded: expanded) { showAgents.toggle() }
            .help("Agents")
            .kajiPopover(isPresented: $showAgents, preferredEdge: .top) {
                AgentMissionControlPanel(onDismiss: { showAgents = false })
            }
    }

    private var collapsedFooter: some View {
        VStack(spacing: 6) {
            agentsButton
            IconButton(symbol: notificationBellIcon, accessibilityLabel: "Notifications") { showNotifications.toggle() }
                .help("Notifications")
                .kajiPopover(isPresented: $showNotifications, preferredEdge: .top) {
                    NotificationPanel(onDismiss: { showNotifications = false })
                }
            IconButton(symbol: "paintbrush", accessibilityLabel: "Theme Picker") { showThemePicker.toggle() }
                .help("Theme Picker (\(KeyBindingStore.shared.combo(for: .toggleThemePicker).displayString))")
                .kajiPopover(isPresented: $showThemePicker, preferredEdge: .top) {
                    ThemePicker(
                        onRequestCreate: {
                            showThemePicker = false
                            NotificationCenter.default.post(name: .requestCreateThemeModal, object: nil)
                        },
                        onDismiss: { showThemePicker = false }
                    )
                }
            SidebarToggleButton(expanded: expanded, accessibilityLabel: sidebarToggleLabel) { postToggleSidebar() }
                .help("\(sidebarToggleLabel) (\(KeyBindingStore.shared.combo(for: .toggleSidebar).displayString))")
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KajiTheme.border)
                .frame(height: 1)
        }
    }

    private var expandedFooter: some View {
        HStack(spacing: 6) {
            SidebarToggleButton(expanded: expanded, accessibilityLabel: sidebarToggleLabel) { postToggleSidebar() }
                .help("\(sidebarToggleLabel) (\(KeyBindingStore.shared.combo(for: .toggleSidebar).displayString))")

            Spacer()

            agentsButton
            IconButton(symbol: notificationBellIcon, accessibilityLabel: "Notifications") { showNotifications.toggle() }
                .help("Notifications")
                .kajiPopover(isPresented: $showNotifications, preferredEdge: .top) {
                    NotificationPanel(onDismiss: { showNotifications = false })
                }
            IconButton(symbol: "paintbrush", accessibilityLabel: "Theme Picker") { showThemePicker.toggle() }
                .help("Theme Picker (\(KeyBindingStore.shared.combo(for: .toggleThemePicker).displayString))")
                .kajiPopover(isPresented: $showThemePicker, preferredEdge: .top) {
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
        .frame(height: KajiLayout.footerBarHeight)
        .background(
            SidebarBackgroundSurface(
                transparencyEnabled: sidebarTransparencyEnabled,
                transparencyAmount: interfaceTransparencyAmount
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KajiTheme.border)
                .frame(height: 1)
        }
    }
}

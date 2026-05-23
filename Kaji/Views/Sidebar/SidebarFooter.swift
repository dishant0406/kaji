import SwiftUI

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
    @State private var updateService = UpdateService.shared

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

    private var collapsedFooter: some View {
        VStack(spacing: 6) {
            updateButton
            agentsButton
            notificationsButton
            themeButton
            sidebarToggleButton
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
            sidebarToggleButton
            Spacer()
            updateButton
            agentsButton
            notificationsButton
            themeButton
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

    @ViewBuilder
    private var updateButton: some View {
        if let version = updateService.availableUpdateVersion {
            SidebarUpdateButton(version: version) {
                updateService.checkForUpdates()
            }
        }
    }

    private var agentsButton: some View {
        AgentMissionControlButton(items: agentItems, expanded: expanded) { showAgents.toggle() }
            .help("Agents")
            .kajiPopover(isPresented: $showAgents, preferredEdge: .top) {
                AgentMissionControlPanel(onDismiss: { showAgents = false })
            }
    }

    private var notificationsButton: some View {
        IconButton(symbol: notificationBellIcon, accessibilityLabel: "Notifications") { showNotifications.toggle() }
            .help("Notifications")
            .kajiPopover(isPresented: $showNotifications, preferredEdge: .top) {
                NotificationPanel(onDismiss: { showNotifications = false })
            }
    }

    private var themeButton: some View {
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

    private var sidebarToggleButton: some View {
        SidebarToggleButton(expanded: expanded, accessibilityLabel: sidebarToggleLabel) { postToggleSidebar() }
            .help("\(sidebarToggleLabel) (\(KeyBindingStore.shared.combo(for: .toggleSidebar).displayString))")
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

    private func postToggleSidebar() {
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }
}

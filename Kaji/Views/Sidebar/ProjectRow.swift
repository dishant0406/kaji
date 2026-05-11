import AppKit
import SwiftUI

struct ProjectRow: View {
    let project: Project
    let shortcutIndex: Int?
    let isAnyDragging: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onRename: (String) -> Void
    let onSetLogo: (String?) -> Void
    let onSetIconColor: (String?) -> Void

    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var activityStore = AIActivityStore.shared
    @State private var notificationStore = NotificationStore.shared
    @State private var codeGraphStore = KajiCodeGraphStore.shared
    @State private var codeGraphRuntime = KajiCodeGraphRuntime.shared
    @State private var codeGraphAgentCoordinator = KajiCodeGraphAgentCoordinator.shared

    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showWorktreePopover = false
    @State private var isGitRepo = false
    @State private var isRefreshingWorktrees = false
    @State private var showColorPicker = false
    @State private var showProjectMenu = false

    private var isActive: Bool {
        appState.activeProjectID == project.id
    }

    private var worktrees: [Worktree] {
        worktreeStore.list(for: project.id)
    }

    private var activeWorktree: Worktree {
        if let activeID = appState.activeWorktreeID[project.id],
           let worktree = worktrees.first(where: { $0.id == activeID })
        {
            return worktree
        }
        return worktrees.first(where: \.isPrimary) ?? Worktree(id: project.id, name: "primary", path: project.path, isPrimary: true)
    }

    private var displayLetter: String {
        String(project.name.prefix(1)).uppercased()
    }

    private var hasOpenTerminal: Bool {
        ProjectSidebarStateResolver.hasOpenTerminal(projectID: project.id, appState: appState)
    }

    private var hasRunningAgent: Bool {
        activityStore.hasActiveAgent(projectID: project.id)
    }

    private var hasCodeGraph: Bool {
        codeGraphRuntime.hasGraph(projectID: project.id, worktreeID: activeWorktree.id)
    }

    private var isCodeGraphRunning: Bool {
        codeGraphRuntime.isRunning(projectID: project.id, worktreeID: activeWorktree.id)
    }

    private var hasCodeGraphAgentSession: Bool {
        codeGraphAgentCoordinator.hasSession(projectID: project.id, worktreeID: activeWorktree.id)
    }

    var body: some View {
        projectIcon
            .help(project.name)
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(project.name)
            .accessibilityValue(isActive ? "Active" : "")
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityAddTraits(.isButton)
            .onHover { hovering in
                guard !isAnyDragging else { return }
                hovered = hovering
            }
            .onChange(of: isAnyDragging) { _, dragging in
                if dragging { hovered = false }
            }
            .kajiPointer()
            .onTapGesture {
                guard !isAnyDragging else { return }
                onSelect()
            }
            .task(id: project.path) {
                isGitRepo = await GitWorktreeService.shared.isGitRepository(project.path)
            }
            .overlay {
                SecondaryClickView {
                    guard !isAnyDragging else { return }
                    showProjectMenu = true
                }
            }
            .kajiPopover(isPresented: $showProjectMenu, preferredEdge: .trailing) {
                ProjectContextMenu(
                    hasLogo: project.logo != nil,
                    hasIconColor: project.iconColor != nil,
                    isGitRepo: isGitRepo,
                    canSwitchWorktree: worktrees.count > 1,
                    isRefreshingWorktrees: isRefreshingWorktrees,
                    isCodeGraphInstalled: codeGraphStore.isInstalled,
                    isCodeGraphEnabled: codeGraphStore.state.isEnabled,
                    hasCodeGraph: hasCodeGraph,
                    isCodeGraphRunning: isCodeGraphRunning,
                    hasCodeGraphAgentSession: hasCodeGraphAgentSession,
                    onSetLogo: {
                        showProjectMenu = false
                        pickLogoImage()
                    },
                    onRemoveLogo: {
                        showProjectMenu = false
                        onSetLogo(nil)
                    },
                    onSetIconColor: {
                        showProjectMenu = false
                        showColorPicker = true
                    },
                    onResetIconColor: {
                        showProjectMenu = false
                        onSetIconColor(nil)
                    },
                    onRename: {
                        showProjectMenu = false
                        startRename()
                    },
                    onRefreshWorktrees: {
                        showProjectMenu = false
                        Task { await refreshWorktrees() }
                    },
                    onNewWorktree: {
                        showProjectMenu = false
                        requestCreateWorktree()
                    },
                    onSwitchWorktree: {
                        showProjectMenu = false
                        showWorktreePopover = true
                    },
                    onInstallCodeGraph: {
                        showProjectMenu = false
                        Task { @MainActor in await KajiCodeGraphInstaller().install(store: codeGraphStore) }
                    },
                    onEnableCodeGraph: {
                        showProjectMenu = false
                        codeGraphStore.setEnabled(true)
                    },
                    onBuildCodeGraph: {
                        showProjectMenu = false
                        buildCodeGraph(mode: "build")
                    },
                    onUpdateCodeGraph: {
                        showProjectMenu = false
                        buildCodeGraph(mode: "update")
                    },
                    onViewCodeGraph: {
                        showProjectMenu = false
                        viewCodeGraph()
                    },
                    onShowCodeGraphAgent: {
                        showProjectMenu = false
                        showCodeGraphAgent()
                    },
                    onRemoveProject: {
                        showProjectMenu = false
                        onRemove()
                    }
                )
            }
            .kajiPopover(isPresented: $showWorktreePopover, preferredEdge: .trailing) {
                WorktreePopover(
                    project: project,
                    isGitRepo: isGitRepo,
                    onDismiss: { showWorktreePopover = false },
                    onRequestCreate: {
                        showWorktreePopover = false
                        requestCreateWorktree()
                    }
                )
                .environment(appState)
                .environment(worktreeStore)
            }
            .overlay {
                if showShortcutBadge, let shortcutIndex,
                   let action = ShortcutAction.projectAction(for: shortcutIndex)
                {
                    ShortcutBadge(label: KeyBindingStore.shared.combo(for: action).displayString)
                }
            }
            .kajiPopover(isPresented: $isRenaming, preferredEdge: .trailing) {
                RenamePopover(
                    text: $renameText,
                    onCommit: { commitRename() },
                    onCancel: { cancelRename() }
                )
            }
            .kajiPopover(isPresented: $showColorPicker, preferredEdge: .trailing) {
                ProjectIconColorPicker(selectedID: project.iconColor) { id in
                    onSetIconColor(id)
                    showColorPicker = false
                }
            }
    }

    private var resolvedLogo: NSImage? {
        guard let filename = project.logo else { return nil }
        return NSImage(contentsOfFile: ProjectLogoStorage.logoPath(for: filename))
    }

    private var projectIcon: some View {
        let logo = resolvedLogo
        let unread = notificationStore.unreadCount(for: project.id)
        return ZStack {
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .fill(iconBackground(hasLogo: logo != nil))

            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            } else {
                Text(displayLetter)
                    .kajiFont(size: 14, weight: .semibold)
                    .foregroundStyle(letterForeground)
            }
        }
        .frame(width: 36, height: 36)
        .shadow(
            color: hasOpenTerminal ? KajiTheme.accent.opacity(isActive ? 0.22 : 0.14) : .clear,
            radius: hasOpenTerminal ? 10 : 0
        )
        .overlay(alignment: .topTrailing) {
            if unread > 0 {
                NotificationBadge(count: unread)
                    .offset(x: 5, y: -5)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .strokeBorder(iconBorderColor, lineWidth: 1)
        }
        .overlay {
            if hasRunningAgent {
                SidebarActivityBorder(
                    cornerRadius: KajiShape.tileRadius,
                    lineWidth: 1
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isRefreshingWorktrees {
                ProgressView()
                    .controlSize(.mini)
                    .padding(4)
            }
        }
    }

    private func iconBackground(hasLogo: Bool) -> AnyShapeStyle {
        if hasLogo { return AnyShapeStyle(Color.clear) }
        if let tint = ProjectIconColor.color(for: project.iconColor) {
            return AnyShapeStyle(hovered ? tint.opacity(0.92) : tint.opacity(isActive ? 0.88 : 0.76))
        }
        if isActive { return AnyShapeStyle(KajiTheme.surface) }
        if hovered { return AnyShapeStyle(KajiTheme.surface) }
        return AnyShapeStyle(KajiTheme.bg)
    }

    private var letterForeground: Color {
        if let foreground = ProjectIconColor.foreground(for: project.iconColor) {
            return foreground
        }
        return isActive ? KajiTheme.fg : (hovered ? KajiTheme.fg : KajiTheme.fgMuted)
    }

    private var iconBorderColor: Color {
        if isActive { return KajiTheme.accent.opacity(0.7) }
        if hasOpenTerminal { return KajiTheme.accent.opacity(0.32) }
        if hovered { return KajiTheme.border }
        return KajiTheme.border.opacity(0.55)
    }

    private var showShortcutBadge: Bool {
        guard let shortcutIndex,
              let action = ShortcutAction.projectAction(for: shortcutIndex)
        else { return false }
        return ModifierKeyMonitor.shared.isHolding(
            modifiers: KeyBindingStore.shared.combo(for: action).modifiers
        )
    }

    private func pickLogoImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Logo Image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url)
        else { return }

        NotificationCenter.default.post(
            name: .requestProjectLogoCropper,
            object: nil,
            userInfo: [
                "projectID": project.id,
                "image": image,
            ]
        )
    }

    private func requestCreateWorktree() {
        NotificationCenter.default.post(
            name: .requestCreateWorktreeModal,
            object: nil,
            userInfo: ["projectID": project.id]
        )
    }

    private func startRename() {
        renameText = project.name
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }

    private func refreshWorktrees() async {
        await WorktreeRefreshHelper.refresh(
            project: project,
            appState: appState,
            worktreeStore: worktreeStore,
            isRefreshing: $isRefreshingWorktrees
        )
    }

    private func buildCodeGraph(mode: String) {
        let worktree = activeWorktree
        Task { @MainActor in
            await codeGraphRuntime.build(KajiCodeGraphRunRequest(
                projectID: project.id,
                worktreeID: worktree.id,
                projectPath: worktree.path,
                mode: mode
            ), appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        }
    }

    private func viewCodeGraph() {
        appState.openCodeGraphTab(
            projectID: project.id,
            worktreeID: activeWorktree.id,
            worktreePath: activeWorktree.path,
            graphURL: codeGraphRuntime.kajiGraphURL(projectID: project.id, worktreeID: activeWorktree.id)
        )
    }

    private func showCodeGraphAgent() {
        codeGraphAgentCoordinator.show(projectID: project.id, worktreeID: activeWorktree.id)
    }
}

private struct RenamePopover: View {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("Rename Project")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            TextField(
                "",
                text: $text,
                prompt: Text("Project name").foregroundStyle(KajiTheme.fgDim)
            )
            .textFieldStyle(.plain)
            .kajiFont(size: 12)
            .foregroundStyle(KajiTheme.fg)
            .focused($isFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .stroke(isFocused ? KajiTheme.accent.opacity(0.6) : KajiTheme.border, lineWidth: 1)
            )
            .onSubmit { onCommit() }
            .onExitCommand { onCancel() }
        }
        .padding(12)
        .frame(width: 200)
        .onAppear { isFocused = true }
    }
}

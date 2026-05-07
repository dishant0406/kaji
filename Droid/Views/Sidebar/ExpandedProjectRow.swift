import AppKit
import SwiftUI

struct ExpandedProjectRow: View {
    let project: Project
    let shortcutIndex: Int?
    let isAnyDragging: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onRename: (String) -> Void
    let onSetLogo: (String?) -> Void
    let onSetIconColor: (String?) -> Void

    @Environment(AppState.self) private var appState
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var activityStore = AIActivityStore.shared
    @State private var notificationStore = NotificationStore.shared
    @State private var codeGraphStore = DroidCodeGraphStore.shared
    @State private var codeGraphRuntime = DroidCodeGraphRuntime.shared

    @AppStorage(GeneralSettingsKeys.autoExpandWorktreesOnProjectSwitch)
    private var autoExpandWorktrees = false

    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isGitRepo = false
    @State private var worktreesExpanded = false
    @State private var isRefreshingWorktrees = false
    @State private var showColorPicker = false
    @State private var showProjectMenu = false

    private var isActive: Bool {
        appState.activeProjectID == project.id
    }

    private var worktrees: [Worktree] {
        worktreeStore.list(for: project.id)
    }

    private var activeWorktreeID: UUID? {
        appState.activeWorktreeID[project.id]
    }

    private var activeWorktree: Worktree? {
        worktrees.first { $0.id == activeWorktreeID }
    }

    private var codeGraphWorktree: Worktree {
        activeWorktree ?? worktrees.first(where: \.isPrimary) ?? Worktree(
            id: project.id,
            name: "primary",
            path: project.path,
            isPrimary: true
        )
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
        codeGraphRuntime.hasGraph(projectID: project.id, worktreeID: codeGraphWorktree.id)
    }

    private var isCodeGraphRunning: Bool {
        codeGraphRuntime.isRunning(projectID: project.id, worktreeID: codeGraphWorktree.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader
            if worktreesExpanded, isGitRepo {
                worktreeList
            }
        }
        .task(id: project.path) {
            isGitRepo = await GitWorktreeService.shared.isGitRepository(project.path)
            if autoExpandWorktrees, isActive, isGitRepo {
                worktreesExpanded = true
            }
        }
        .onChange(of: isActive) { _, active in
            guard autoExpandWorktrees, active, isGitRepo else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                worktreesExpanded = true
            }
        }
        .droidPopover(isPresented: $isRenaming, preferredEdge: .trailing) {
            ExpandedRenamePopover(
                text: $renameText,
                onCommit: { commitRename() },
                onCancel: { cancelRename() }
            )
        }
        .droidPopover(isPresented: $showColorPicker, preferredEdge: .trailing) {
            ProjectIconColorPicker(selectedID: project.iconColor) { id in
                onSetIconColor(id)
                showColorPicker = false
            }
        }
    }

    private var projectHeader: some View {
        HStack(spacing: 8) {
            projectIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .droidFont(size: 12, weight: isActive ? .semibold : .medium)
                    .foregroundStyle(isActive ? DroidTheme.fg : (hovered ? DroidTheme.fg : DroidTheme.fgMuted))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isGitRepo, let worktree = activeWorktree, !worktreesExpanded {
                    Text(worktree.isPrimary ? "primary" : worktree.name)
                        .droidFont(size: 10, design: .monospaced)
                        .foregroundStyle(DroidTheme.fgDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if isGitRepo {
                worktreeChevron
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(headerBackground, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(projectHeaderAccessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
        .onHover { hovering in
            guard !isAnyDragging else { return }
            hovered = hovering
        }
        .onChange(of: isAnyDragging) { _, dragging in
            if dragging { hovered = false }
        }
        .onTapGesture {
            guard !isAnyDragging else { return }
            if isActive, isGitRepo {
                withAnimation(.easeInOut(duration: 0.15)) {
                    worktreesExpanded.toggle()
                }
            } else {
                onSelect()
            }
        }
        .overlay {
            ZStack {
                if hasRunningAgent {
                    SidebarActivityBorder(
                        cornerRadius: DroidShape.tileRadius,
                        lineWidth: 1
                    )
                }

                if showShortcutBadge, let shortcutIndex,
                   let action = ShortcutAction.projectAction(for: shortcutIndex)
                {
                    ShortcutBadge(label: KeyBindingStore.shared.combo(for: action).displayString)
                }
            }
        }
        .overlay {
            SecondaryClickView {
                guard !isAnyDragging else { return }
                showProjectMenu = true
            }
        }
        .droidPopover(isPresented: $showProjectMenu, preferredEdge: .trailing) {
            ProjectContextMenu(
                hasLogo: project.logo != nil,
                hasIconColor: project.iconColor != nil,
                isGitRepo: isGitRepo,
                canSwitchWorktree: false,
                isRefreshingWorktrees: isRefreshingWorktrees,
                isCodeGraphInstalled: codeGraphStore.isInstalled,
                isCodeGraphEnabled: codeGraphStore.state.isEnabled,
                hasCodeGraph: hasCodeGraph,
                isCodeGraphRunning: isCodeGraphRunning,
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
                },
                onInstallCodeGraph: {
                    showProjectMenu = false
                    Task { @MainActor in await DroidCodeGraphInstaller().install(store: codeGraphStore) }
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
                onRemoveProject: {
                    showProjectMenu = false
                    onRemove()
                }
            )
        }
    }

    private var worktreeChevron: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                worktreesExpanded.toggle()
            }
        } label: {
            DroidIcon(systemName: worktreesExpanded ? "chevron.down" : "chevron.right", size: 9)
                .foregroundStyle(DroidTheme.fgDim)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(worktreesExpanded ? "Collapse Worktrees" : "Expand Worktrees")
    }

    private var projectIcon: some View {
        let logo = resolvedLogo
        let unread = notificationStore.unreadCount(for: project.id)
        return ZStack {
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .fill(iconBackground(hasLogo: logo != nil))

            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            } else {
                Text(displayLetter)
                    .droidFont(size: 11, weight: .semibold)
                    .foregroundStyle(letterForeground)
            }
        }
        .frame(width: 26, height: 26)
        .shadow(
            color: hasOpenTerminal ? DroidTheme.accent.opacity(isActive ? 0.18 : 0.12) : .clear,
            radius: hasOpenTerminal ? 10 : 0
        )
        .overlay {
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .strokeBorder(iconBorderColor, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if unread > 0 {
                NotificationBadge(count: unread)
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var worktreeList: some View {
        SidebarWorktreeSection(
            projectID: project.id,
            worktrees: worktrees,
            activeWorktreeID: activeWorktreeID,
            onSelect: { worktree in
                appState.selectWorktree(projectID: project.id, worktree: worktree)
            },
            onRename: { worktree, newName in
                worktreeStore.rename(
                    worktreeID: worktree.id,
                    in: project.id,
                    to: newName
                )
            },
            onRemove: { worktree in
                Task { await requestRemove(worktree: worktree) }
            },
            onCreate: {
                requestCreateWorktree()
            }
        )
    }

    private var projectHeaderAccessibilityLabel: String {
        var label = project.name
        if isGitRepo, let worktree = activeWorktree {
            label += ", worktree: \(worktree.isPrimary ? "primary" : worktree.name)"
        }
        return label
    }

    private var resolvedLogo: NSImage? {
        guard let filename = project.logo else { return nil }
        return NSImage(contentsOfFile: ProjectLogoStorage.logoPath(for: filename))
    }

    private func iconBackground(hasLogo: Bool) -> AnyShapeStyle {
        if hasLogo { return AnyShapeStyle(Color.clear) }
        if let tint = ProjectIconColor.color(for: project.iconColor) {
            return AnyShapeStyle(hovered ? tint.opacity(0.88) : tint.opacity(isActive ? 0.84 : 0.72))
        }
        if isActive { return AnyShapeStyle(DroidTheme.tertiaryBackground) }
        if hovered { return AnyShapeStyle(DroidTheme.tertiaryBackground) }
        return AnyShapeStyle(DroidTheme.secondaryBackground)
    }

    private var letterForeground: Color {
        if let foreground = ProjectIconColor.foreground(for: project.iconColor) {
            return foreground
        }
        return isActive ? DroidTheme.fg : (hovered ? DroidTheme.fg : DroidTheme.fgMuted)
    }

    private var headerBackground: AnyShapeStyle {
        if isActive { return AnyShapeStyle(DroidTheme.surface) }
        if hasOpenTerminal { return AnyShapeStyle(DroidTheme.secondaryBackground) }
        if hovered { return AnyShapeStyle(DroidTheme.hover) }
        return AnyShapeStyle(Color.clear)
    }

    private var iconBorderColor: Color {
        if isActive { return DroidTheme.border.opacity(0.7) }
        if hasOpenTerminal { return DroidTheme.accent.opacity(0.28) }
        if hovered { return DroidTheme.border.opacity(0.65) }
        return .clear
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
        worktreesExpanded = true
        NotificationCenter.default.post(
            name: .requestCreateWorktreeModal,
            object: nil,
            userInfo: ["projectID": project.id]
        )
    }

    private func requestRemove(worktree: Worktree) async {
        let hasChanges = await GitWorktreeService.shared.hasUncommittedChanges(worktreePath: worktree.path)
        if !hasChanges {
            performRemove(worktree: worktree)
            return
        }
        presentRemoveConfirmation(worktree: worktree)
    }

    private func presentRemoveConfirmation(worktree: Worktree) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let alert = NSAlert()
        alert.messageText = "Remove worktree \"\(worktree.name)\"?"
        alert.informativeText = "This worktree has uncommitted changes. Removing it will permanently discard them."
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            performRemove(worktree: worktree)
        }
    }

    private func performRemove(worktree: Worktree) {
        let repoPath = project.path
        let remaining = worktrees.filter { $0.id != worktree.id }
        let replacement = remaining.first(where: { $0.id == activeWorktreeID })
            ?? remaining.first(where: { $0.isPrimary })
            ?? remaining.first
        appState.removeWorktree(
            projectID: project.id,
            worktree: worktree,
            replacement: replacement
        )
        worktreeStore.remove(worktreeID: worktree.id, from: project.id)
        Task.detached {
            await WorktreeStore.cleanupOnDisk(
                worktree: worktree,
                repoPath: repoPath
            )
        }
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
        let worktree = codeGraphWorktree
        Task { @MainActor in
            await codeGraphRuntime.build(DroidCodeGraphRunRequest(
                projectID: project.id,
                worktreeID: worktree.id,
                projectPath: worktree.path,
                mode: mode
            ))
        }
    }

    private func viewCodeGraph() {
        appState.openCodeGraphTab(
            projectID: project.id,
            worktreeID: codeGraphWorktree.id,
            worktreePath: codeGraphWorktree.path,
            graphURL: codeGraphRuntime.droidGraphURL(projectID: project.id, worktreeID: codeGraphWorktree.id)
        )
    }
}

private struct ExpandedRenamePopover: View {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("Rename Project")
                .droidFont(size: 12, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            TextField(
                "",
                text: $text,
                prompt: Text("Project name").foregroundStyle(DroidTheme.fgDim)
            )
            .textFieldStyle(.plain)
            .droidFont(size: 12)
            .foregroundStyle(DroidTheme.fg)
            .focused($isFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DroidTheme.surface, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .stroke(isFocused ? DroidTheme.accent.opacity(0.6) : DroidTheme.border, lineWidth: 1)
            )
            .onSubmit { onCommit() }
            .onExitCommand { onCancel() }
        }
        .padding(12)
        .frame(width: 200)
        .onAppear { isFocused = true }
    }
}

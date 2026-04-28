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
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var activityStore = AIActivityStore.shared
    @State private var notificationStore = NotificationStore.shared

    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showWorktreePopover = false
    @State private var isGitRepo = false
    @State private var logoCropImage: IdentifiableImage?
    @State private var isRefreshingWorktrees = false
    @State private var showColorPicker = false

    private var isActive: Bool {
        appState.activeProjectID == project.id
    }

    private var worktrees: [Worktree] {
        worktreeStore.list(for: project.id)
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

    var body: some View {
        projectIcon
            .help(project.name)
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
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
            .onTapGesture {
                guard !isAnyDragging else { return }
                onSelect()
            }
            .task(id: project.path) {
                isGitRepo = await GitWorktreeService.shared.isGitRepository(project.path)
            }
            .contextMenu {
                Button("Set Logo...") { pickLogoImage() }
                if project.logo != nil {
                    Button("Remove Logo") { onSetLogo(nil) }
                }
                Button("Set Icon Color...") { showColorPicker = true }
                if project.iconColor != nil {
                    Button("Reset Icon Color") { onSetIconColor(nil) }
                }
                Divider()
                Button("Rename Project") { startRename() }
                if isGitRepo {
                    Divider()
                    Button("Refresh Worktrees") { Task { await refreshWorktrees() } }
                    Button("New Worktree…") { requestCreateWorktree() }
                    if worktrees.count > 1 {
                        Button("Switch Worktree…") { showWorktreePopover = true }
                    }
                }
                Divider()
                Button("Remove Project", role: .destructive, action: onRemove)
            }
            .droidPopover(isPresented: $showWorktreePopover, preferredEdge: .trailing) {
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
            .sheet(item: $logoCropImage) { item in
                LogoCropperSheet(
                    sourceImage: item.image,
                    onConfirm: { cropped in
                        logoCropImage = nil
                        let logoPath = ProjectLogoStorage.save(
                            croppedImage: cropped,
                            forProjectID: project.id
                        )
                        onSetLogo(logoPath)
                    },
                    onCancel: { logoCropImage = nil }
                )
            }
            .overlay {
                if showShortcutBadge, let shortcutIndex,
                   let action = ShortcutAction.projectAction(for: shortcutIndex)
                {
                    ShortcutBadge(label: KeyBindingStore.shared.combo(for: action).displayString)
                }
            }
            .droidPopover(isPresented: $isRenaming, preferredEdge: .trailing) {
                RenamePopover(
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

    private var resolvedLogo: NSImage? {
        guard let filename = project.logo else { return nil }
        return NSImage(contentsOfFile: ProjectLogoStorage.logoPath(for: filename))
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
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            } else {
                Text(displayLetter)
                    .droidFont(size: 14, weight: .semibold)
                    .foregroundStyle(letterForeground)
            }
        }
        .frame(width: 36, height: 36)
        .shadow(
            color: hasOpenTerminal ? DroidTheme.accent.opacity(isActive ? 0.22 : 0.14) : .clear,
            radius: hasOpenTerminal ? 10 : 0
        )
        .overlay(alignment: .topTrailing) {
            if unread > 0 {
                NotificationBadge(count: unread)
                    .offset(x: 5, y: -5)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .strokeBorder(iconBorderColor, lineWidth: 1)
        }
        .overlay {
            if hasRunningAgent {
                SidebarActivityBorder(
                    cornerRadius: DroidShape.tileRadius,
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
        if isActive { return AnyShapeStyle(DroidTheme.surface) }
        if hovered { return AnyShapeStyle(DroidTheme.surface) }
        return AnyShapeStyle(DroidTheme.bg)
    }

    private var letterForeground: Color {
        if let foreground = ProjectIconColor.foreground(for: project.iconColor) {
            return foreground
        }
        return isActive ? DroidTheme.fg : (hovered ? DroidTheme.fg : DroidTheme.fgMuted)
    }

    private var iconBorderColor: Color {
        if isActive { return DroidTheme.accent.opacity(0.7) }
        if hasOpenTerminal { return DroidTheme.accent.opacity(0.32) }
        if hovered { return DroidTheme.border }
        return DroidTheme.border.opacity(0.55)
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

        logoCropImage = IdentifiableImage(image: image)
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
}

private struct RenamePopover: View {
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

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: NSImage
}

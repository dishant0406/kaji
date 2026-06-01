import SwiftUI

struct SidebarWorktreeSection: View {
    let projectID: UUID
    let worktrees: [Worktree]
    let activeWorktreeID: UUID?
    let onSelect: (Worktree) -> Void
    let onRename: (Worktree, String) -> Void
    let onRemove: (Worktree) -> Void
    let onCreate: () -> Void
    var accessory: AnyView = AnyView(EmptyView())

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(KajiTheme.border.opacity(0.7))
                .frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(worktrees) { worktree in
                    SidebarWorktreeRow(
                        projectID: projectID,
                        worktree: worktree,
                        selected: worktree.id == activeWorktreeID,
                        onSelect: { onSelect(worktree) },
                        onRename: { onRename(worktree, $0) },
                        onRemove: worktree.canBeRemoved ? { onRemove(worktree) } : nil
                    )
                }
                accessory
                SidebarNewWorktreeRow(action: onCreate)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
        }
    }
}

struct SidebarWorktreeRow: View {
    let projectID: UUID
    let worktree: Worktree
    let selected: Bool
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onRemove: (() -> Void)?

    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var notificationStore = NotificationStore.shared
    @FocusState private var renameFieldFocused: Bool

    private var displayName: String {
        worktree.isPrimary && worktree.name.isEmpty ? "main" : worktree.name
    }

    private var branchLabel: String? {
        guard let branch = worktree.branch, !branch.isEmpty else { return nil }
        guard branch.caseInsensitiveCompare(displayName) != .orderedSame else { return nil }
        return branch
    }

    var body: some View {
        HStack(spacing: 8) {
            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                HStack(spacing: 6) {
                    Text(displayName)
                        .kajiFont(size: 12, weight: selected ? .semibold : .regular)
                        .foregroundStyle(selected ? KajiTheme.fg : KajiTheme.fgMuted)
                        .lineLimit(1)
                    if let detailLabel {
                        Text(detailLabel)
                            .kajiFont(size: 11, weight: .regular, design: .monospaced)
                            .foregroundStyle(KajiTheme.fgDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 0)
            let unread = notificationStore.unreadCount(for: projectID, worktreeID: worktree.id)
            if unread > 0 {
                NotificationBadge(count: unread)
            }
            if selected {
                KajiIcon(systemName: "checkmark", size: 9)
                    .foregroundStyle(KajiTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(KajiMotion.fast, value: selected)
        .animation(KajiMotion.hover, value: hovered)
        .kajiHoverEffect(isActive: hovered && !isRenaming, scale: 1.01)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: selected, isEnabled: selected)
        .kajiPointer()
        .onTapGesture {
            guard !isRenaming else { return }
            onSelect()
        }
        .contextMenu {
            if worktree.isPrimary {
                Text("Primary worktree").kajiFont(size: 11)
            } else if let onRemove {
                Button("Rename") { startRename() }
                Divider()
                Button("Remove", role: .destructive, action: onRemove)
            } else {
                Button("Rename") { startRename() }
                Divider()
                Text("External worktree").kajiFont(size: 11)
            }
        }
    }

    private var detailLabel: String? {
        if worktree.isPrimary { return "primary" }
        return branchLabel
    }

    private var rowBackground: Color {
        if selected { return KajiTheme.surfaceMuted }
        if hovered { return KajiTheme.hover.opacity(0.7) }
        return .clear
    }

    private func startRename() {
        renameText = worktree.name
        isRenaming = true
        renameFieldFocused = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { onRename(trimmed) }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }
}

struct SidebarNewWorktreeRow: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                KajiIcon(systemName: "plus", size: 11)
                    .foregroundStyle(hovered ? KajiTheme.fg : KajiTheme.fgDim)
                Text("New Worktree")
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(hovered ? KajiTheme.fg : KajiTheme.fgMuted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(hovered ? KajiTheme.hover.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .kajiHoverEffect(isActive: hovered, scale: 1.012)
        .kajiChangeFeedback(KajiMotion.tapFeedback, value: hovered, isEnabled: hovered)
        .kajiPointer()
        .accessibilityLabel("New Worktree")
    }
}

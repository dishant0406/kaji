import SwiftUI

struct SidebarWorktreeSection: View {
    let projectID: UUID
    let worktrees: [Worktree]
    let activeWorktreeID: UUID?
    let onSelect: (Worktree) -> Void
    let onRename: (Worktree, String) -> Void
    let onRemove: (Worktree) -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(DroidTheme.border.opacity(0.7))
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
                    .droidFont(size: 12, weight: .medium)
                    .foregroundStyle(DroidTheme.fg)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                HStack(spacing: 6) {
                    Text(displayName)
                        .droidFont(size: 12, weight: selected ? .semibold : .regular)
                        .foregroundStyle(selected ? DroidTheme.fg : DroidTheme.fgMuted)
                        .lineLimit(1)
                    if let detailLabel {
                        Text(detailLabel)
                            .droidFont(size: 11, weight: .regular, design: .monospaced)
                            .foregroundStyle(DroidTheme.fgDim)
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
                DroidIcon(systemName: "checkmark", size: 9)
                    .foregroundStyle(DroidTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            guard !isRenaming else { return }
            onSelect()
        }
        .contextMenu {
            if worktree.isPrimary {
                Text("Primary worktree").droidFont(size: 11)
            } else if let onRemove {
                Button("Rename") { startRename() }
                Divider()
                Button("Remove", role: .destructive, action: onRemove)
            } else {
                Button("Rename") { startRename() }
                Divider()
                Text("External worktree").droidFont(size: 11)
            }
        }
    }

    private var detailLabel: String? {
        if worktree.isPrimary { return "primary" }
        return branchLabel
    }

    private var rowBackground: Color {
        if selected { return DroidTheme.surfaceMuted }
        if hovered { return DroidTheme.hover.opacity(0.7) }
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
                DroidIcon(systemName: "plus", size: 11)
                    .foregroundStyle(hovered ? DroidTheme.fg : DroidTheme.fgDim)
                Text("New Worktree")
                    .droidFont(size: 12, weight: .medium)
                    .foregroundStyle(hovered ? DroidTheme.fg : DroidTheme.fgMuted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(hovered ? DroidTheme.hover.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("New Worktree")
    }
}

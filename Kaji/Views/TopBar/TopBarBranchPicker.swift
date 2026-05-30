import SwiftUI

struct TopBarBranchPicker: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var state = TopBarBranchState()
    @State private var showPopover = false
    @State private var hovered = false

    private var repoPath: String? {
        guard let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return nil }
        guard let key = appState.activeWorktreeKey(for: projectID) else { return project.path }
        return worktreeStore.worktree(projectID: projectID, worktreeID: key.worktreeID)?.path ?? project.path
    }

    private var branchItems: [BranchItem] {
        state.branches.map { BranchItem(name: $0) }
    }

    var body: some View {
        Group {
            if repoPath != nil {
                button
            }
        }
        .onAppear { state.refresh(repoPath: repoPath) }
        .onChange(of: repoPath) { _, path in state.refresh(repoPath: path) }
        .onReceive(NotificationCenter.default.publisher(for: .vcsRepoDidChange)) { notification in
            guard let changedPath = notification.userInfo?["repoPath"] as? String,
                  changedPath == repoPath
            else { return }
            state.reload()
        }
    }

    private var button: some View {
        Button {
            state.reload()
            showPopover.toggle()
        } label: {
            HStack(spacing: 7) {
                KajiIcon(systemName: "arrow.triangle.branch", size: 12)
                    .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
                Text(state.currentBranch ?? "detached")
                    .kajiFont(size: 12, weight: .medium, design: .monospaced)
                    .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 150, alignment: .leading)
                KajiIcon(systemName: "chevron.down", size: 8)
                    .foregroundStyle(KajiTheme.fgDim)
                    .rotationEffect(.degrees(showPopover ? 180 : 0))
                    .animation(KajiMotion.fast, value: showPopover)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(active ? KajiTheme.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .strokeBorder(KajiTheme.border.opacity(active ? 0.85 : 0.35), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.borderless)
        .disabled(state.isSwitching)
        .onHover { hovered = $0 }
        .kajiHoverEffect(isActive: active)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: state.currentBranch ?? "")
        .kajiChangeFeedback(KajiMotion.attentionFeedback, value: state.isSwitching, isEnabled: state.isSwitching)
        .kajiPointer()
        .help(state.currentBranch ?? "Branch")
        .accessibilityLabel("Git Branch")
        .kajiPopover(isPresented: $showPopover, preferredEdge: .bottom) {
            PopoverPicker(
                items: branchItems,
                filterKey: \.name,
                searchPlaceholder: "Search branches",
                emptyLabel: state.isLoading ? "Loading..." : "No branches found",
                emptyActionTitle: createBranchTitle(for:),
                emptyActionDetail: "Create and switch to this branch",
                height: popoverHeight,
                onEmptyAction: { branch in
                    showPopover = false
                    state.createAndSwitchBranch(branch)
                },
                onSelect: { item in
                    showPopover = false
                    state.switchBranch(item.name)
                },
                row: { item, isHighlighted in
                    TopBarBranchRow(
                        name: item.name,
                        isActive: item.name == state.currentBranch,
                        isHighlighted: isHighlighted
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
            )
        }
    }

    private var active: Bool {
        showPopover || hovered || state.isSwitching
    }

    private var popoverHeight: CGFloat {
        let rowCount = max(min(state.branches.count, 8), 1)
        return CGFloat(rowCount * 40 + 54)
    }

    private func createBranchTitle(for query: String) -> String? {
        guard !state.isLoading,
              let branch = GitRepositoryService.normalizedBranchName(query),
              !state.branches.contains(branch),
              branch != state.currentBranch
        else { return nil }
        return "Create branch \(branch)"
    }
}

private struct BranchItem: Identifiable {
    let name: String
    var id: String { name }
}

private struct TopBarBranchRow: View {
    let name: String
    let isActive: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .kajiFont(size: 12, weight: isActive ? .semibold : .medium, design: .monospaced)
                .foregroundStyle(KajiTheme.fg)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isActive {
                KajiIcon(systemName: "checkmark", size: 10)
                    .foregroundStyle(KajiTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .animation(KajiMotion.fast, value: isHighlighted)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: isActive, isEnabled: isActive)
    }

    private var rowBackground: Color {
        if isActive { return KajiTheme.accentSoft }
        if isHighlighted { return KajiTheme.surface }
        return .clear
    }
}

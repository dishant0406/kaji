import SwiftUI

struct AgentMissionControlPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var runStore = AgentRunStore.shared
    @State private var notificationStore = NotificationStore.shared
    let onDismiss: () -> Void

    private var items: [AgentMissionControlItem] {
        _ = notificationStore.readStateVersion
        return AgentRunMissionControlSnapshotBuilder.items(
            runs: runStore.runs,
            notifications: notificationStore.notifications,
            projects: projectStore.projects,
            worktrees: worktreeStore.worktrees
        )
    }

    private var sections: [AgentMissionControlSection] {
        AgentMissionControlSectionBuilder.sections(for: items)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DroidTheme.border)
            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 380, height: 420)
        .background(DroidTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.panelRadius))
    }

    private var header: some View {
        HStack(spacing: 8) {
            DroidIcon(systemName: "rectangle.stack", size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
            Text("Agents")
                .droidFont(size: 12, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Spacer()
            DroidBadge(text: "\(items.count)", variant: items.contains { $0.status == .needsAttention } ? .warning : .neutral)
            Button(action: onDismiss) {
                DroidIcon(systemName: "xmark", size: 11)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DroidTheme.fgMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(sections) { section in
                    AgentMissionControlSectionHeader(section: section)
                    ForEach(section.items) { item in
                        AgentMissionControlRow(
                            item: item,
                            onVerify: verify(item),
                            onOpenFile: openFile(item),
                            onOpenDiff: openDiff(item)
                        ) {
                            AgentMissionControlNavigator.navigate(
                                to: item,
                                appState: appState,
                                worktreeStore: worktreeStore,
                                notificationStore: notificationStore
                            )
                            onDismiss()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(DroidTheme.bg.opacity(0.28))
    }

    private func verify(_ item: AgentMissionControlItem) -> (() -> Void)? {
        guard let runID = item.runID else { return nil }
        guard !item.changedFiles.isEmpty else { return nil }
        return {
            AgentVerificationRunner.verify(runID: runID, store: runStore)
        }
    }

    private func openFile(_ item: AgentMissionControlItem) -> ((AgentChangedFile) -> Void)? {
        guard let runID = item.runID else { return nil }
        return { file in
            guard file.status != .deleted,
                  let context = activateContext(for: runID)
            else { return }
            let filePath = (context.worktreePath as NSString).appendingPathComponent(file.path)
            appState.openFile(filePath, projectID: context.projectID)
            onDismiss()
        }
    }

    private func openDiff(_ item: AgentMissionControlItem) -> ((AgentChangedFile) -> Void)? {
        guard let runID = item.runID else { return nil }
        return { file in
            guard let context = activateContext(for: runID) else { return }
            appState.openDiffViewer(
                vcs: VCSTabState(projectPath: context.worktreePath),
                filePath: file.path,
                isStaged: false,
                projectID: context.projectID
            )
            onDismiss()
        }
    }

    private func activateContext(for runID: UUID) -> (projectID: UUID, worktreePath: String)? {
        guard let run = runStore.run(id: runID),
              let projectID = run.projectID,
              let worktreePath = run.worktreePath,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return nil }

        guard let worktree = worktree(for: run, projectID: projectID, worktreePath: worktreePath) else { return nil }
        appState.selectProject(project, worktree: worktree)
        return (projectID, worktree.path)
    }

    private func worktree(for run: AgentRun, projectID: UUID, worktreePath: String) -> Worktree? {
        if let worktreeID = run.worktreeID,
           let worktree = worktreeStore.worktree(projectID: projectID, worktreeID: worktreeID)
        {
            return worktree
        }
        return worktreeStore.list(for: projectID).first { $0.path == worktreePath }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            DroidIcon(systemName: "checkmark.circle", size: 22)
                .foregroundStyle(DroidTheme.fgDim)
            Text("No agent runs")
                .droidFont(size: 12, weight: .medium)
                .foregroundStyle(DroidTheme.fgMuted)
            Text("Active sessions and recent provider updates will appear here.")
                .droidFont(size: 11)
                .foregroundStyle(DroidTheme.fgDim)
                .multilineTextAlignment(.center)
                .frame(width: 240)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DroidTheme.bg.opacity(0.28))
    }
}

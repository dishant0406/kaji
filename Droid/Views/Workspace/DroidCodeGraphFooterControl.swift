import SwiftUI

struct DroidCodeGraphFooterControl: View {
    let projectID: UUID
    let worktreeKey: WorktreeKey?
    let worktreePath: String?
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var store = DroidCodeGraphStore.shared
    @State private var runtime = DroidCodeGraphRuntime.shared
    @State private var agentCoordinator = DroidCodeGraphAgentCoordinator.shared
    @State private var showsPopover = false
    @State private var confirmsDelete = false

    var body: some View {
        if store.isReady, let context {
            IconButton(
                symbol: "atom",
                selected: showsPopover || isRunning(context),
                accessibilityLabel: "Code Graph"
            ) {
                showsPopover.toggle()
            }
            .help("Code Graph")
            .droidPopover(isPresented: $showsPopover, preferredEdge: .top) {
                DroidCodeGraphFooterPopover(
                    hasGraph: hasGraph(context),
                    isRunning: isRunning(context),
                    hasAgentSession: hasAgentSession(context),
                    lastError: lastError(context),
                    onView: { view(context) },
                    onBuild: { build(context, mode: "build") },
                    onUpdate: { build(context, mode: "update") },
                    onDelete: { confirmsDelete = true },
                    onShowAgent: { showAgent(context) }
                )
            }
            .alert("Delete Code Graph?", isPresented: $confirmsDelete) {
                Button("Delete", role: .destructive) {
                    delete(context)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes Droid's generated graph, graph versions, and graph instruction files for this worktree.")
            }
        }
    }

    private var context: DroidCodeGraphFooterContext? {
        guard let worktreeKey,
              worktreeKey.projectID == projectID,
              let worktreePath
        else { return nil }
        return DroidCodeGraphFooterContext(
            projectID: projectID,
            worktreeID: worktreeKey.worktreeID,
            projectPath: worktreePath
        )
    }

    private func hasGraph(_ context: DroidCodeGraphFooterContext) -> Bool {
        runtime.hasGraph(projectID: context.projectID, worktreeID: context.worktreeID)
    }

    private func isRunning(_ context: DroidCodeGraphFooterContext) -> Bool {
        runtime.isRunning(projectID: context.projectID, worktreeID: context.worktreeID)
    }

    private func hasAgentSession(_ context: DroidCodeGraphFooterContext) -> Bool {
        agentCoordinator.hasSession(projectID: context.projectID, worktreeID: context.worktreeID)
    }

    private func lastError(_ context: DroidCodeGraphFooterContext) -> String? {
        runtime.lastError["\(context.projectID.uuidString)-\(context.worktreeID.uuidString)"]
    }

    private func view(_ context: DroidCodeGraphFooterContext) {
        guard hasGraph(context) else { return }
        showsPopover = false
        appState.openCodeGraphTab(
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            worktreePath: context.projectPath,
            graphURL: runtime.droidGraphURL(projectID: context.projectID, worktreeID: context.worktreeID)
        )
    }

    private func build(_ context: DroidCodeGraphFooterContext, mode: String) {
        guard !isRunning(context) else { return }
        showsPopover = false
        Task { @MainActor in
            await runtime.build(DroidCodeGraphRunRequest(
                projectID: context.projectID,
                worktreeID: context.worktreeID,
                projectPath: context.projectPath,
                mode: mode
            ), appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        }
    }

    private func delete(_ context: DroidCodeGraphFooterContext) {
        try? DroidCodeGraphArtifacts.delete(projectID: context.projectID, worktreeID: context.worktreeID)
        runtime.lastStatus.removeValue(forKey: "\(context.projectID.uuidString)-\(context.worktreeID.uuidString)")
        runtime.lastError.removeValue(forKey: "\(context.projectID.uuidString)-\(context.worktreeID.uuidString)")
        showsPopover = false
    }

    private func showAgent(_ context: DroidCodeGraphFooterContext) {
        showsPopover = false
        agentCoordinator.show(projectID: context.projectID, worktreeID: context.worktreeID)
    }
}

private struct DroidCodeGraphFooterContext {
    let projectID: UUID
    let worktreeID: UUID
    let projectPath: String
}

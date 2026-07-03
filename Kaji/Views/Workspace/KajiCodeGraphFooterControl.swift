import SwiftUI

struct KajiCodeGraphFooterControl: View {
    let projectID: UUID
    let worktreeKey: WorktreeKey?
    let worktreePath: String?
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var store = KajiCodeGraphStore.shared
    @State private var runtime = KajiCodeGraphRuntime.shared
    @State private var agentCoordinator = KajiCodeGraphAgentCoordinator.shared
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
            .kajiPopover(isPresented: $showsPopover, preferredEdge: .top) {
                KajiCodeGraphFooterPopover(
                    hasGraph: hasGraph(context),
                    isRunning: isRunning(context),
                    hasAgentSession: hasAgentSession(context),
                    lastError: lastError(context),
                    onView: { view(context) },
                    onBuild: { build(context, mode: "build") },
                    onUpdate: { build(context, mode: "update") },
                    onDelete: { confirmsDelete = true },
                    onShowAgent: { showAgent(context) },
                    onCopyCodeGraph: { KajiCodeGraphPromptClipboard.copyCodeGraphDocument() },
                    onCopyAgentsReference: { KajiCodeGraphPromptClipboard.copyAgentsReference() }
                )
            }
            .alert("Delete Code Graph?", isPresented: $confirmsDelete) {
                Button("Delete", role: .destructive) {
                    delete(context)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes Kaji's generated graph, graph versions, and graph instruction files for this worktree.")
            }
        }
    }

    private var context: KajiCodeGraphFooterContext? {
        guard let worktreeKey,
              worktreeKey.projectID == projectID,
              let worktreePath
        else { return nil }
        return KajiCodeGraphFooterContext(
            projectID: projectID,
            worktreeID: worktreeKey.worktreeID,
            projectPath: worktreePath
        )
    }

    private func hasGraph(_ context: KajiCodeGraphFooterContext) -> Bool {
        runtime.hasGraph(projectID: context.projectID, worktreeID: context.worktreeID)
    }

    private func isRunning(_ context: KajiCodeGraphFooterContext) -> Bool {
        runtime.isRunning(projectID: context.projectID, worktreeID: context.worktreeID)
    }

    private func hasAgentSession(_ context: KajiCodeGraphFooterContext) -> Bool {
        agentCoordinator.hasSession(projectID: context.projectID, worktreeID: context.worktreeID)
    }

    private func lastError(_ context: KajiCodeGraphFooterContext) -> String? {
        runtime.lastError["\(context.projectID.uuidString)-\(context.worktreeID.uuidString)"]
    }

    private func view(_ context: KajiCodeGraphFooterContext) {
        guard hasGraph(context) else { return }
        showsPopover = false
        appState.openCodeGraphTab(
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            worktreePath: context.projectPath,
            graphURL: runtime.kajiGraphURL(projectID: context.projectID, worktreeID: context.worktreeID)
        )
    }

    private func build(_ context: KajiCodeGraphFooterContext, mode: String) {
        guard !isRunning(context) else { return }
        showsPopover = false
        Task { @MainActor in
            await runtime.build(KajiCodeGraphRunRequest(
                projectID: context.projectID,
                worktreeID: context.worktreeID,
                projectPath: context.projectPath,
                mode: mode
            ), appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        }
    }

    private func delete(_ context: KajiCodeGraphFooterContext) {
        try? KajiCodeGraphArtifacts.delete(projectID: context.projectID, worktreeID: context.worktreeID)
        runtime.lastStatus.removeValue(forKey: "\(context.projectID.uuidString)-\(context.worktreeID.uuidString)")
        runtime.lastError.removeValue(forKey: "\(context.projectID.uuidString)-\(context.worktreeID.uuidString)")
        showsPopover = false
    }

    private func showAgent(_ context: KajiCodeGraphFooterContext) {
        showsPopover = false
        agentCoordinator.show(projectID: context.projectID, worktreeID: context.worktreeID)
    }
}

private struct KajiCodeGraphFooterContext {
    let projectID: UUID
    let worktreeID: UUID
    let projectPath: String
}

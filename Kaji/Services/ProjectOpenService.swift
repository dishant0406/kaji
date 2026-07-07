import AppKit

@MainActor
enum ProjectOpenService {
    static func openProject(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try ProjectSelectionService.selectOrAddProject(
                path: url.path(percentEncoded: false),
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        } catch {
            DebugFileLog.log("Projects", "Failed to open project \(url.path): \(error.localizedDescription)")
        }
    }
}

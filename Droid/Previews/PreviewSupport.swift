import Foundation

@MainActor
struct PreviewStores {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore

    static func make() -> PreviewStores {
        let projects = sampleProjects()
        let worktreesByProject = Dictionary(uniqueKeysWithValues: projects.map { project in
            (
                project.id,
                [
                    Worktree(
                        name: project.name,
                        path: project.path,
                        branch: "main",
                        source: .droid,
                        isPrimary: true
                    ),
                ]
            )
        })

        let projectStore = ProjectStore(persistence: PreviewProjectPersistence(projects: projects))
        let worktreeStore = WorktreeStore(
            persistence: PreviewWorktreePersistence(worktreesByProject: worktreesByProject),
            projects: projects
        )
        let selectionStore = PreviewSelectionStore(
            activeProjectID: projects.first?.id,
            activeWorktreeIDs: Dictionary(uniqueKeysWithValues: worktreesByProject.compactMap { projectID, worktrees in
                guard let worktree = worktrees.first else { return nil }
                return (projectID, worktree.id)
            })
        )
        let appState = AppState(
            selectionStore: selectionStore,
            terminalViews: PreviewTerminalViewStore(),
            workspacePersistence: PreviewWorkspacePersistence()
        )
        appState.restoreSelection(projects: projectStore.projects, worktrees: worktreeStore.worktrees)
        return PreviewStores(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
    }

    private static func sampleProjects() -> [Project] {
        [
            makeProject(name: "Droid", sortOrder: 0, iconColor: "blue"),
            makeProject(name: "Ghostty", sortOrder: 1, iconColor: "green"),
            makeProject(name: "Website", sortOrder: 2, iconColor: "orange"),
        ]
    }

    private static func makeProject(name: String, sortOrder: Int, iconColor: String) -> Project {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("droid-preview", isDirectory: true)
            .appendingPathComponent(name.lowercased(), isDirectory: true)
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        var project = Project(name: name, path: path.path, sortOrder: sortOrder)
        project.iconColor = iconColor
        return project
    }
}

private final class PreviewProjectPersistence: ProjectPersisting {
    private let projects: [Project]

    init(projects: [Project]) {
        self.projects = projects
    }

    func loadProjects() throws -> [Project] {
        projects
    }

    func saveProjects(_ projects: [Project]) throws {}
}

private final class PreviewWorktreePersistence: WorktreePersisting {
    private let worktreesByProject: [UUID: [Worktree]]

    init(worktreesByProject: [UUID: [Worktree]]) {
        self.worktreesByProject = worktreesByProject
    }

    func loadWorktrees(projectID: UUID) throws -> [Worktree] {
        worktreesByProject[projectID] ?? []
    }

    func saveWorktrees(_ worktrees: [Worktree], projectID: UUID) throws {}

    func removeWorktrees(projectID: UUID) throws {}
}

private final class PreviewSelectionStore: ActiveProjectSelectionStoring {
    private var activeProjectID: UUID?
    private var activeWorktreeIDs: [UUID: UUID]

    init(activeProjectID: UUID?, activeWorktreeIDs: [UUID: UUID]) {
        self.activeProjectID = activeProjectID
        self.activeWorktreeIDs = activeWorktreeIDs
    }

    func loadActiveProjectID() -> UUID? {
        activeProjectID
    }

    func saveActiveProjectID(_ id: UUID?) {
        activeProjectID = id
    }

    func loadActiveWorktreeIDs() -> [UUID: UUID] {
        activeWorktreeIDs
    }

    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {
        activeWorktreeIDs = ids
    }
}

private final class PreviewWorkspacePersistence: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] {
        []
    }

    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
}

private final class PreviewTerminalViewStore: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}

    func needsConfirmQuit(for paneID: UUID) -> Bool {
        false
    }
}

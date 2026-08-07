import Foundation

enum ProjectSelectionServiceError: LocalizedError, Equatable {
    case emptyPath
    case directoryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .emptyPath:
            "Project path is empty."
        case let .directoryNotFound(path):
            "Project folder does not exist: \(path)"
        }
    }
}

struct ProjectSelectionResult: Equatable {
    let projectID: UUID
    let worktreeID: UUID
    let addedProject: Bool
}

@MainActor
enum ProjectSelectionService {
    static func selectOrAddProject(
        path rawPath: String,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        fileManager: FileManager = .default
    ) throws -> ProjectSelectionResult {
        let path = try resolvedDirectoryPath(rawPath, fileManager: fileManager)
        if let match = existingSelection(for: path, projects: projectStore.projects, worktreeStore: worktreeStore) {
            appState.selectProject(match.project, worktree: match.worktree)
            return ProjectSelectionResult(projectID: match.project.id, worktreeID: match.worktree.id, addedProject: false)
        }

        let project = Project(
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            sortOrder: projectStore.nextSortOrder()
        )
        projectStore.add(project)
        worktreeStore.ensurePrimary(for: project)
        guard let primary = worktreeStore.primary(for: project.id) else {
            throw ProjectSelectionServiceError.directoryNotFound(path)
        }
        appState.selectProject(project, worktree: primary)
        return ProjectSelectionResult(projectID: project.id, worktreeID: primary.id, addedProject: true)
    }

    private static func existingSelection(
        for path: String,
        projects: [Project],
        worktreeStore: WorktreeStore
    ) -> (project: Project, worktree: Worktree)? {
        let target = canonicalPath(path)
        for project in projects {
            if canonicalPath(project.path) == target {
                worktreeStore.ensurePrimary(for: project)
                guard let primary = worktreeStore.primary(for: project.id) else { continue }
                return (project, primary)
            }
            if let worktree = worktreeStore.list(for: project.id).first(where: { canonicalPath($0.path) == target }) {
                return (project, worktree)
            }
        }
        return nil
    }

    private static func resolvedDirectoryPath(_ rawPath: String, fileManager: FileManager) throws -> String {
        guard !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectSelectionServiceError.emptyPath
        }
        let expanded = (rawPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, relativeTo: nil)
        let absolute = url.path.hasPrefix("/") ? url : URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent(expanded)
        let path = canonicalPath(absolute.path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectSelectionServiceError.directoryNotFound(path)
        }
        return path
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

import Foundation
import os

let worktreeStoreLogger = Logger(subsystem: "app.kaji", category: "WorktreeStore")

@MainActor
@Observable
final class WorktreeStore {
    private(set) var worktrees: [UUID: [Worktree]] = [:]
    private var projectIDByPath: [String: UUID] = [:]
    private let persistence: any WorktreePersisting
    let listRiftWorkspaces: @Sendable (String) async throws -> [RiftWorkspaceRecord]

    init(
        persistence: any WorktreePersisting,
        listRiftWorkspaces: @escaping @Sendable (String) async throws -> [RiftWorkspaceRecord] = {
            try await RiftWorkspaceService.shared.listWorkspaces(of: $0)
        },
        projects: [Project] = []
    ) {
        self.persistence = persistence
        self.listRiftWorkspaces = listRiftWorkspaces
        guard !projects.isEmpty else { return }
        loadAll(projects: projects)
    }

    func loadAll(projects: [Project]) {
        for project in projects {
            do {
                var loaded = try persistence.loadWorktrees(projectID: project.id)
                if !loaded.contains(where: \.isPrimary) {
                    loaded.insert(makePrimary(for: project), at: 0)
                    try? persistence.saveWorktrees(loaded, projectID: project.id)
                }
                setWorktrees(sortPrimaryFirst(loaded), for: project.id)
            } catch {
                worktreeStoreLogger.error("Failed to load worktrees for project \(project.id): \(error)")
                setWorktrees([makePrimary(for: project)], for: project.id)
                save(projectID: project.id)
            }
        }
    }

    func ensurePrimary(for project: Project) {
        var list = worktrees[project.id] ?? []
        if list.contains(where: \.isPrimary) { return }
        list.insert(makePrimary(for: project), at: 0)
        setWorktrees(sortPrimaryFirst(list), for: project.id)
        save(projectID: project.id)
    }

    func list(for projectID: UUID) -> [Worktree] {
        worktrees[projectID] ?? []
    }

    func projectID(forWorktreePath path: String) -> UUID? {
        projectIDByPath[path]
    }

    func primary(for projectID: UUID) -> Worktree? {
        list(for: projectID).first(where: { $0.isPrimary })
    }

    func worktree(projectID: UUID, worktreeID: UUID) -> Worktree? {
        list(for: projectID).first(where: { $0.id == worktreeID })
    }

    func preferred(for projectID: UUID, matching preferredID: UUID?) -> Worktree? {
        let list = list(for: projectID)
        return list.first(where: { $0.id == preferredID })
            ?? list.first(where: { $0.isPrimary })
            ?? list.first
    }

    func add(_ worktree: Worktree, to projectID: UUID) {
        var list = worktrees[projectID] ?? []
        list.append(worktree)
        setWorktrees(sortPrimaryFirst(list), for: projectID)
        save(projectID: projectID)
    }

    func remove(worktreeID: UUID, from projectID: UUID) {
        guard var list = worktrees[projectID] else { return }
        list.removeAll { $0.id == worktreeID && $0.canBeRemoved }
        setWorktrees(list, for: projectID)
        save(projectID: projectID)
    }

    func rename(worktreeID: UUID, in projectID: UUID, to newName: String) {
        guard var list = worktrees[projectID],
              let index = list.firstIndex(where: { $0.id == worktreeID })
        else { return }
        list[index].name = newName
        setWorktrees(list, for: projectID)
        save(projectID: projectID)
    }

    func updateBranch(worktreeID: UUID, in projectID: UUID, branch: String?) {
        guard var list = worktrees[projectID],
              let index = list.firstIndex(where: { $0.id == worktreeID })
        else { return }
        list[index].branch = branch
        setWorktrees(list, for: projectID)
        save(projectID: projectID)
    }

    @discardableResult
    func removeProject(_ projectID: UUID) -> Bool {
        if let existing = worktrees[projectID] {
            for worktree in existing where projectIDByPath[worktree.path] == projectID {
                projectIDByPath.removeValue(forKey: worktree.path)
            }
        }
        worktrees.removeValue(forKey: projectID)
        do {
            try persistence.removeWorktrees(projectID: projectID)
            return true
        } catch {
            worktreeStoreLogger.error("Failed to remove worktrees file for project \(projectID): \(error)")
            return false
        }
    }

    func setWorktrees(_ list: [Worktree], for projectID: UUID) {
        if let previous = worktrees[projectID] {
            for worktree in previous where projectIDByPath[worktree.path] == projectID {
                projectIDByPath.removeValue(forKey: worktree.path)
            }
        }
        for worktree in list {
            projectIDByPath[worktree.path] = projectID
        }
        worktrees[projectID] = list
    }

    func makePrimary(for project: Project) -> Worktree {
        Worktree(
            name: project.name,
            path: project.path,
            branch: nil,
            source: .kaji,
            backend: .primary,
            isPrimary: true
        )
    }

    func sortPrimaryFirst(_ list: [Worktree]) -> [Worktree] {
        let primary = list.filter(\.isPrimary)
        let others = list.filter { !$0.isPrimary }.sorted { $0.createdAt < $1.createdAt }
        return primary + others
    }

    func save(projectID: UUID) {
        guard let list = worktrees[projectID] else { return }
        do {
            try persistence.saveWorktrees(list, projectID: projectID)
        } catch {
            worktreeStoreLogger.error("Failed to save worktrees for project \(projectID): \(error)")
        }
    }
}

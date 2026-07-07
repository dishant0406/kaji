import Foundation

@MainActor
extension WorktreeStore {
    func refreshFromRift(project: Project) async throws -> [Worktree] {
        ensurePrimary(for: project)
        let records = try await listRiftWorkspaces(project.path)
        var list = worktrees[project.id] ?? []
        let projectKey = Self.canonicalPath(project.path)
        let recordKeys = Set(records.map { Self.canonicalPath($0.path) })

        if let primaryIndex = list.firstIndex(where: \.isPrimary) {
            list[primaryIndex].path = project.path
            list[primaryIndex].name = project.name
            list[primaryIndex].backend = .primary
        } else {
            list.insert(makePrimary(for: project), at: 0)
        }

        var existingByKey: [String: Worktree] = [:]
        for worktree in list {
            let key = Self.canonicalPath(worktree.path)
            if let existing = existingByKey[key] {
                if worktree.isPrimary, !existing.isPrimary {
                    existingByKey[key] = worktree
                }
            } else {
                existingByKey[key] = worktree
            }
        }

        for record in records where Self.canonicalPath(record.path) != projectKey {
            let recordKey = Self.canonicalPath(record.path)
            if let existing = existingByKey[recordKey],
               let index = list.firstIndex(where: { $0.id == existing.id })
            {
                list[index].backend = list[index].source == .external ? .externalRift : .rift
                list[index].riftID = record.riftID
                continue
            }

            list.append(Worktree(
                name: defaultName(for: record),
                path: record.path,
                branch: nil,
                source: .external,
                backend: .externalRift,
                riftID: record.riftID,
                isPrimary: false
            ))
        }

        let sorted = sortPrimaryFirst(list.filter {
            !$0.isExternallyManaged || recordKeys.contains(Self.canonicalPath($0.path))
        })
        setWorktrees(sorted, for: project.id)
        save(projectID: project.id)
        return sorted
    }

    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func defaultName(for record: RiftWorkspaceRecord) -> String {
        URL(fileURLWithPath: record.path).lastPathComponent
    }
}

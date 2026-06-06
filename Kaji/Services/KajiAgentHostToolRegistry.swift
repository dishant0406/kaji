import Foundation

@MainActor
enum KajiAgentHostToolRegistry {
    static let definitions = KajiAgentHostToolCatalog.definitions
    static let uriSchemes = KajiAgentHostToolCatalog.uriSchemes

    static func execute(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) async -> KajiAgentToolResult {
        switch frame.toolName {
        case "kaji_get_active_context":
            activeContext(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_open_file":
            openFile(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_open_terminal":
            openTerminal(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_fff_find":
            await fffFind(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_fff_search":
            await fffSearch(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        default:
            error("Unsupported Kaji host tool: \(frame.toolName ?? "unknown")")
        }
    }

    static func resolveURI(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentHostURIResult {
        let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        return KajiAgentHostURIResolver.resolve(frame, rootPath: context?.worktree.path)
    }

    private static func activeContext(
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore) else {
            return error("No active Kaji project.")
        }
        return text([
            "Active project: \(context.project.name)",
            "Project path: \(context.project.path)",
            "Worktree: \(context.worktree.name)",
            "Worktree path: \(context.worktree.path)",
        ].joined(separator: "\n"))
    }

    private static func openFile(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore) else {
            return error("No active Kaji project.")
        }
        guard let rawPath = frame.arguments?["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty else {
            return error("path is required.")
        }
        guard let path = KajiAgentWorkspacePathResolver.resolve(rawPath, rootPath: context.worktree.path) else {
            return error("File path is outside the active Kaji worktree.")
        }
        context.appState.selectProject(context.project, worktree: context.worktree)
        context.appState.openFile(path, projectID: context.project.id)
        return text("Opened \(path).")
    }

    private static func openTerminal(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore) else {
            return error("No active Kaji project.")
        }
        let title = frame.arguments?["title"]?.stringValue?.nilIfEmpty ?? "Terminal"
        let command = frame.arguments?["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        context.appState.selectProject(context.project, worktree: context.worktree)
        if command.isEmpty {
            context.appState.createTab(projectID: context.project.id)
        } else {
            context.appState.createCommandTab(projectID: context.project.id, title: title, command: command)
        }
        return text(command.isEmpty ? "Opened terminal." : "Opened command terminal.")
    }

    private static func fffFind(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) async -> KajiAgentToolResult {
        guard let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore) else {
            return error("No active Kaji project.")
        }
        guard let query = frame.arguments?["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return error("query is required.")
        }
        let limit = min(max(frame.arguments?["limit"]?.numberValue.map(Int.init) ?? 30, 1), 100)
        do {
            let started = Date()
            let results = try await FFFSearchService.searchFiles(query: query, in: context.worktree.path, limit: limit)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            KajiAgentEventLog.record("fff_find", fields: [
                "query": .string(query),
                "count": .number(Double(results.count)),
                "elapsedMs": .number(Double(elapsed)),
            ])
            let body = results.enumerated().map { index, result in
                "\(index + 1). \(result.relativePath)"
            }.joined(separator: "\n")
            return text(results.isEmpty ? "No files found for \"\(query)\"." : "Found \(results.count) files in \(elapsed)ms:\n\(body)")
        } catch {
            return Self.error(error.localizedDescription)
        }
    }

    private static func fffSearch(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) async -> KajiAgentToolResult {
        guard let context = activeWorkspace(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore) else {
            return error("No active Kaji project.")
        }
        guard let query = frame.arguments?["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return error("query is required.")
        }
        let limit = min(max(frame.arguments?["limit"]?.numberValue.map(Int.init) ?? 120, 1), 300)
        do {
            let started = Date()
            let groups = try await FFFSearchService.searchText(query: query, in: context.worktree.path, limit: limit)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            let matchCount = groups.reduce(0) { $0 + $1.matches.count }
            KajiAgentEventLog.record("fff_search", fields: [
                "query": .string(query),
                "fileCount": .number(Double(groups.count)),
                "matchCount": .number(Double(matchCount)),
                "elapsedMs": .number(Double(elapsed)),
            ])
            guard !groups.isEmpty else { return text("No matches found for \"\(query)\".") }
            let body = groups.map { group in
                let matches = group.matches.prefix(6).map { match in
                    "  \(match.line):\(match.column): \(match.preview)"
                }.joined(separator: "\n")
                let suffix = group.matches.count > 6 ? "\n  ... \(group.matches.count - 6) more matches" : ""
                return "\(group.relativePath)\n\(matches)\(suffix)"
            }.joined(separator: "\n\n")
            return text("Found \(matchCount) matches in \(groups.count) files in \(elapsed)ms:\n\(body)")
        } catch {
            return Self.error(error.localizedDescription)
        }
    }

    private static func activeWorkspace(
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentWorkspaceContext? {
        guard let appState, let projectStore, let worktreeStore,
              let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return nil }
        worktreeStore.ensurePrimary(for: project)
        let worktree = appState.activeWorktreeKey(for: project.id)
            .flatMap { worktreeStore.worktree(projectID: project.id, worktreeID: $0.worktreeID) }
            ?? worktreeStore.primary(for: project.id)
            ?? Worktree(name: project.name, path: project.path, isPrimary: true)
        return KajiAgentWorkspaceContext(appState: appState, project: project, worktree: worktree)
    }

    private static func text(_ value: String) -> KajiAgentToolResult {
        KajiAgentToolResult(content: [KajiAgentContentBlock(type: "text", text: value)], details: nil, isError: false)
    }

    private static func error(_ value: String) -> KajiAgentToolResult {
        KajiAgentToolResult(content: [KajiAgentContentBlock(type: "text", text: value)], details: nil, isError: true)
    }
}

private struct KajiAgentWorkspaceContext {
    let appState: AppState
    let project: Project
    let worktree: Worktree
}

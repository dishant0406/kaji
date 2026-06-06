import Foundation

@MainActor
enum KajiAgentCodeGraphHostTools {
    static func report(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        let url = KajiCodeGraphRuntime.shared.reportURL(projectID: context.project.id, worktreeID: context.worktree.id)
        let graphURL = KajiCodeGraphRuntime.shared.kajiGraphURL(projectID: context.project.id, worktreeID: context.worktree.id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return KajiAgentCodeGraphMissingResult.report(reportURL: url, graphURL: graphURL)
        }
        let maxLines = frame.arguments?["max_lines"]?.numberValue.map(Int.init)
            ?? frame.arguments?["maxLines"]?.numberValue.map(Int.init)
            ?? 160
        do {
            let body = try KajiCodeGraphAgentQuery.report(url: url, maxLines: maxLines)
            return KajiAgentHostToolResult.text(body, details: .object(["path": .string(url.path)]))
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }

    static func search(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        guard let query = frame.arguments?["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return KajiAgentHostToolResult.error("query is required.")
        }
        let graphURL = KajiCodeGraphRuntime.shared.kajiGraphURL(projectID: context.project.id, worktreeID: context.worktree.id)
        let reportURL = KajiCodeGraphRuntime.shared.reportURL(projectID: context.project.id, worktreeID: context.worktree.id)
        guard FileManager.default.fileExists(atPath: graphURL.path) else {
            return KajiAgentCodeGraphMissingResult.graph(reportURL: reportURL, graphURL: graphURL)
        }
        let limit = frame.arguments?["limit"]?.numberValue.map(Int.init) ?? 20
        do {
            let result = try KajiCodeGraphAgentQuery.search(graphURL: graphURL, query: query, limit: limit)
            return KajiAgentHostToolResult.text(result.text, details: result.details)
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }

    static func neighbors(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        let id = frame.arguments?["id"]?.stringValue
        let label = frame.arguments?["label"]?.stringValue
        let path = frame.arguments?["path"]?.stringValue
        guard [id, label, path].contains(where: { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) else {
            return KajiAgentHostToolResult.error("id, label, or path is required.")
        }
        let graphURL = KajiCodeGraphRuntime.shared.kajiGraphURL(projectID: context.project.id, worktreeID: context.worktree.id)
        let reportURL = KajiCodeGraphRuntime.shared.reportURL(projectID: context.project.id, worktreeID: context.worktree.id)
        guard FileManager.default.fileExists(atPath: graphURL.path) else {
            return KajiAgentCodeGraphMissingResult.graph(reportURL: reportURL, graphURL: graphURL)
        }
        let limit = frame.arguments?["limit"]?.numberValue.map(Int.init) ?? 40
        do {
            guard let result = try KajiCodeGraphAgentQuery.neighbors(graphURL: graphURL, id: id, label: label, path: path, limit: limit)
            else {
                return KajiAgentHostToolResult.error("No matching graph node found.")
            }
            return KajiAgentHostToolResult.text(result.text, details: result.details)
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }

    static func path(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        let graphURL = KajiCodeGraphRuntime.shared.kajiGraphURL(projectID: context.project.id, worktreeID: context.worktree.id)
        let reportURL = KajiCodeGraphRuntime.shared.reportURL(projectID: context.project.id, worktreeID: context.worktree.id)
        guard FileManager.default.fileExists(atPath: graphURL.path) else {
            return KajiAgentCodeGraphMissingResult.graph(reportURL: reportURL, graphURL: graphURL)
        }
        let from = KajiCodeGraphNodeQuery(
            id: frame.arguments?["from_id"]?.stringValue ?? frame.arguments?["fromId"]?.stringValue,
            label: frame.arguments?["from_label"]?.stringValue ?? frame.arguments?["fromLabel"]?.stringValue,
            path: frame.arguments?["from_path"]?.stringValue ?? frame.arguments?["fromPath"]?.stringValue
        )
        let to = KajiCodeGraphNodeQuery(
            id: frame.arguments?["to_id"]?.stringValue ?? frame.arguments?["toId"]?.stringValue,
            label: frame.arguments?["to_label"]?.stringValue ?? frame.arguments?["toLabel"]?.stringValue,
            path: frame.arguments?["to_path"]?.stringValue ?? frame.arguments?["toPath"]?.stringValue
        )
        guard hasNodeQuery(from), hasNodeQuery(to) else {
            return KajiAgentHostToolResult.error("from_* and to_* node selectors are required.")
        }
        let maxDepth = frame.arguments?["max_depth"]?.numberValue.map(Int.init)
            ?? frame.arguments?["maxDepth"]?.numberValue.map(Int.init)
            ?? 4
        do {
            guard let result = try KajiCodeGraphAgentQuery.path(graphURL: graphURL, from: from, to: to, maxDepth: maxDepth) else {
                return KajiAgentHostToolResult.error("No matching source or target graph node found.")
            }
            return KajiAgentHostToolResult.text(result.text, details: result.details)
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }

    static func hotspots(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        let graphURL = KajiCodeGraphRuntime.shared.kajiGraphURL(projectID: context.project.id, worktreeID: context.worktree.id)
        let reportURL = KajiCodeGraphRuntime.shared.reportURL(projectID: context.project.id, worktreeID: context.worktree.id)
        guard FileManager.default.fileExists(atPath: graphURL.path) else {
            return KajiAgentCodeGraphMissingResult.graph(reportURL: reportURL, graphURL: graphURL)
        }
        let limit = frame.arguments?["limit"]?.numberValue.map(Int.init) ?? 20
        do {
            let result = try KajiCodeGraphAgentQuery.hotspots(graphURL: graphURL, limit: limit)
            return KajiAgentHostToolResult.text(result.text, details: result.details)
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }

    private static func hasNodeQuery(_ query: KajiCodeGraphNodeQuery) -> Bool {
        [query.id, query.label, query.path].contains { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }
}

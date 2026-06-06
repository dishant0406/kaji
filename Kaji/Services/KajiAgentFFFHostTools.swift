import Foundation

@MainActor
enum KajiAgentFFFHostTools {
    static func find(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) async -> KajiAgentToolResult {
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
        let limit = min(max(frame.arguments?["limit"]?.numberValue.map(Int.init) ?? 30, 1), 100)
        do {
            let started = Date()
            let results = try await FFFSearchService.searchFiles(query: query, in: context.worktree.path, limit: limit)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            KajiAgentEventLog.record(
                "fff_find",
                fields: ["query": .string(query), "count": .number(Double(results.count)), "elapsedMs": .number(Double(elapsed))]
            )
            let body = results.enumerated().map { index, result in "\(index + 1). \(result.relativePath)" }.joined(separator: "\n")
            return KajiAgentHostToolResult
                .text(results.isEmpty ? "No files found for \"\(query)\"." : "Found \(results.count) files in \(elapsed)ms:\n\(body)")
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }

    static func search(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) async -> KajiAgentToolResult {
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
        let limit = min(max(frame.arguments?["limit"]?.numberValue.map(Int.init) ?? 120, 1), 300)
        do {
            let started = Date()
            let groups = try await FFFSearchService.searchText(query: query, in: context.worktree.path, limit: limit)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            let matchCount = groups.reduce(0) { $0 + $1.matches.count }
            KajiAgentEventLog.record(
                "fff_search",
                fields: [
                    "query": .string(query),
                    "fileCount": .number(Double(groups.count)),
                    "matchCount": .number(Double(matchCount)),
                    "elapsedMs": .number(Double(elapsed)),
                ]
            )
            guard !groups.isEmpty else { return KajiAgentHostToolResult.text("No matches found for \"\(query)\".") }
            let body = groups.map { group in
                let matches = group.matches.prefix(6).map { match in "  \(match.line):\(match.column): \(match.preview)" }
                    .joined(separator: "\n")
                let suffix = group.matches.count > 6 ? "\n  ... \(group.matches.count - 6) more matches" : ""
                return "\(group.relativePath)\n\(matches)\(suffix)"
            }.joined(separator: "\n\n")
            return KajiAgentHostToolResult.text("Found \(matchCount) matches in \(groups.count) files in \(elapsed)ms:\n\(body)")
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }
}

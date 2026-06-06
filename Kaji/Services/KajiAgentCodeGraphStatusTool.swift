import Foundation

enum KajiAgentCodeGraphStatusTool {
    struct Snapshot {
        let hasActiveProject: Bool
        let hasReport: Bool
        let hasGraph: Bool
        let isRunning: Bool
        let reportURL: URL?
        let graphURL: URL?
        let lastError: String?
    }

    @MainActor
    static func status(
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
            return result(Snapshot(
                hasActiveProject: false,
                hasReport: false,
                hasGraph: false,
                isRunning: false,
                reportURL: nil,
                graphURL: nil,
                lastError: nil
            ))
        }
        let runtime = KajiCodeGraphRuntime.shared
        let reportURL = runtime.reportURL(projectID: context.project.id, worktreeID: context.worktree.id)
        let graphURL = runtime.kajiGraphURL(projectID: context.project.id, worktreeID: context.worktree.id)
        let key = "\(context.project.id.uuidString)-\(context.worktree.id.uuidString)"
        return result(Snapshot(
            hasActiveProject: true,
            hasReport: FileManager.default.fileExists(atPath: reportURL.path),
            hasGraph: FileManager.default.fileExists(atPath: graphURL.path),
            isRunning: runtime.isRunning(projectID: context.project.id, worktreeID: context.worktree.id),
            reportURL: reportURL,
            graphURL: graphURL,
            lastError: runtime.lastError[key]
        ))
    }

    static func result(_ snapshot: Snapshot) -> KajiAgentToolResult {
        let ready = snapshot.hasActiveProject && snapshot.hasReport && snapshot.hasGraph && !snapshot.isRunning
        let message = message(snapshot, ready: ready)
        var details: [String: KajiAgentJSONValue] = [
            "kind": .string("codeGraphStatus"),
            "hasActiveProject": .bool(snapshot.hasActiveProject),
            "hasReport": .bool(snapshot.hasReport),
            "hasGraph": .bool(snapshot.hasGraph),
            "ready": .bool(ready),
            "isRunning": .bool(snapshot.isRunning),
            "message": .string(message),
        ]
        if let reportURL = snapshot.reportURL {
            details["reportPath"] = .string(reportURL.path)
        }
        if let graphURL = snapshot.graphURL {
            details["graphPath"] = .string(graphURL.path)
        }
        if let lastError = snapshot.lastError, !lastError.isEmpty {
            details["lastError"] = .string(lastError)
        }
        return KajiAgentHostToolResult.text(message, details: .object(details))
    }

    private static func message(_ snapshot: Snapshot, ready: Bool) -> String {
        if !snapshot.hasActiveProject {
            return "CodeGraph ready: no\nNo active Kaji project is selected."
        }
        if snapshot.isRunning {
            return "CodeGraph ready: no\nA KajiCodeGraph build is currently running for the active worktree."
        }
        if ready {
            return "CodeGraph ready: yes"
        }
        let missing = [snapshot.hasReport ? nil : "report", snapshot.hasGraph ? nil : "graph"].compactMap(\.self)
            .joined(separator: " and ")
        let suffix = snapshot.lastError?.nilIfEmpty.map { "\nLast build error: \($0)" } ?? ""
        return "CodeGraph ready: no\nMissing KajiCodeGraph \(missing). Build it from the Code Graph footer button first.\(suffix)"
    }
}

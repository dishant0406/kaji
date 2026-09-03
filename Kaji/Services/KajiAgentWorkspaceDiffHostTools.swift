import Foundation

@MainActor
enum KajiAgentWorkspaceDiffHostTools {
    static func showDiff(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) async -> KajiAgentToolResult {
        guard let snapshot = KajiAgentWorkspaceStateSnapshot.activeWorkspace(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else { return KajiAgentHostToolResult.error("No active Kaji project.") }
        do {
            let path = try relativePathArgument(frame, root: snapshot.context.worktree.path, required: false)
            let lineLimit = Int(frame.arguments?["lineLimit"]?.numberValue ?? 5000)
            let arguments = diffArguments(path: path)
            let result = try await GitProcessRunner.runGit(
                repoPath: snapshot.context.worktree.path,
                arguments: arguments,
                lineLimit: lineLimit
            )
            guard result.status == 0 else {
                return KajiAgentHostToolResult.error(result.stderr.nilIfEmpty ?? "Failed to load git diff.")
            }
            let text = result.stdout.nilIfEmpty ?? "No diff for the requested scope."
            return KajiAgentHostToolResult.text(text, details: .object([
                "path": path.map { .string($0) } ?? .null,
                "truncated": .bool(result.truncated),
            ]))
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }

    static func openDiff(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) async -> KajiAgentToolResult {
        guard let snapshot = KajiAgentWorkspaceStateSnapshot.activeWorkspace(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else { return KajiAgentHostToolResult.error("No active Kaji project.") }
        do {
            let path = try relativePathArgument(frame, root: snapshot.context.worktree.path, required: false)
            let isStaged = frame.arguments?["isStaged"]?.boolValue ?? false
            let files = try await GitRepositoryService().changedFiles(repoPath: snapshot.context.worktree.path)
            let vcs = KajiAgentWorkspaceStateSnapshot.activeVCSTab(in: snapshot.workspace, fallbackPath: snapshot.context.worktree.path)
            vcs.files = files
            snapshot.context.appState.selectProject(snapshot.context.project, worktree: snapshot.context.worktree)
            if let path {
                snapshot.context.appState.openDiffViewer(
                    vcs: vcs,
                    filePath: path,
                    isStaged: isStaged,
                    projectID: snapshot.context.project.id
                )
                return KajiAgentHostToolResult.text("Opened diff for \(path).")
            }
            snapshot.context.appState.openAllChangesDiffViewer(vcs: vcs, projectID: snapshot.context.project.id)
            return KajiAgentHostToolResult.text("Opened all changes diff viewer.")
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }

    private static func diffArguments(path: String?) -> [String] {
        var arguments = ["-c", "core.quotepath=false", "diff", "HEAD", "--no-color", "--no-ext-diff"]
        if let path {
            arguments.append(contentsOf: ["--", path])
        }
        return arguments
    }

    private static func relativePathArgument(_ frame: KajiAgentRPCFrame, root: String, required: Bool) throws -> String? {
        guard let rawPath = frame.arguments?["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty else {
            if required {
                throw HostToolArgumentError.message("path is required.")
            }
            return nil
        }
        guard let path = KajiAgentWorkspaceStateSnapshot.resolveRelativePath(rawPath, root: root) else {
            throw HostToolArgumentError.message("File path is outside the active Kaji worktree.")
        }
        return path
    }
}

enum HostToolArgumentError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(value): value
        }
    }
}

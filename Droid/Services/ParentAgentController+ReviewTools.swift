import Foundation

@MainActor
extension ParentAgentController {
    func createWorktree(_ message: ParentAgentEnvelope, toolID: String) async {
        guard let appState,
              let projectStore,
              let worktreeStore
        else {
            sendToolError(id: toolID, message: "Droid workspace is unavailable.")
            return
        }
        guard let project = resolveProject(message.arguments?["project"], projectStore: projectStore, appState: appState) else {
            sendToolError(id: toolID, message: "No target project is selected or matched.")
            return
        }
        let name = message.arguments?["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            sendToolError(id: toolID, message: "create_worktree requires a name.")
            return
        }
        let branch = message.arguments?["branch"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
        guard !branch.isEmpty else {
            sendToolError(id: toolID, message: "create_worktree requires a branch.")
            return
        }
        let createBranch = message.arguments?["createBranch"] != "false"
        let path = DroidFileStorage.worktreeDirectory(forProjectID: project.id, name: worktreeSlug(from: name))
            .path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: path) else {
            sendToolError(id: toolID, message: "A worktree with this name already exists on disk.")
            return
        }
        do {
            try await GitWorktreeService.shared.addWorktree(repoPath: project.path, path: path, branch: branch, createBranch: createBranch)
            let worktree = Worktree(name: name, path: path, branch: branch, ownsBranch: createBranch, isPrimary: false)
            worktreeStore.add(worktree, to: project.id)
            appState.selectProject(project, worktree: worktree)
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: toolID,
                ok: true,
                result: ParentAgentToolResult(
                    activeProject: projectContext(project),
                    message: "Created worktree \(worktree.name).",
                    worktree: worktreeContext(worktree)
                )
            ))
        } catch {
            sendToolError(id: toolID, message: error.localizedDescription)
        }
    }

    func getChangedFiles(_ message: ParentAgentEnvelope, toolID: String) async {
        guard let target = resolveWorktreeTarget(message) else {
            sendToolError(id: toolID, message: "No worktree is available.")
            return
        }
        guard let files = await AgentChangedFilesSnapshotter.snapshot(repoPath: target.worktree.path) else {
            sendToolError(id: toolID, message: "Changed files are unavailable for \(target.worktree.name).")
            return
        }
        updateRunChangedFilesIfRequested(message, files: files)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(
                activeProject: projectContext(target.project),
                message: "Found \(files.count) changed files.",
                changedFiles: files.map(changedFileContext)
            )
        ))
    }

    func openDiff(_ message: ParentAgentEnvelope, toolID: String) {
        guard let appState else {
            sendToolError(id: toolID, message: "Droid workspace is unavailable.")
            return
        }
        if let run = resolveRunArgument(message), let file = resolveChangedFile(message, in: run) {
            guard let projectStore, let worktreeStore else {
                sendToolError(id: toolID, message: "Droid workspace is unavailable.")
                return
            }
            sendControlResult(
                AgentControlCenter(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore).perform(.openDiff(run.id, file)),
                toolID: toolID
            )
            return
        }
        guard let target = resolveWorktreeTarget(message) else {
            sendToolError(id: toolID, message: "No worktree is available.")
            return
        }
        guard let path = message.arguments?["path"]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            sendToolError(id: toolID, message: "open_diff requires a file path.")
            return
        }
        appState.selectProject(target.project, worktree: target.worktree)
        appState.openDiffViewer(
            vcs: VCSTabState(projectPath: target.worktree.path),
            filePath: path,
            isStaged: message.arguments?["staged"] == "true",
            projectID: target.project.id
        )
        process.send(ParentAgentEnvelope(type: "tool_result", id: toolID, ok: true, result: ParentAgentToolResult(message: "Opened diff.")))
    }

    func runVerification(_ message: ParentAgentEnvelope, toolID: String) {
        guard let run = resolveRunArgument(message) else {
            sendToolError(id: toolID, message: "run_verification requires a tracked runID.")
            return
        }
        let project: Project? = if let projectID = run.projectID {
            projectStore?.projects.first { $0.id == projectID }
        } else {
            nil
        }
        AgentVerificationRunner.verify(runID: run.id, project: project)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(message: "Verification started.", verification: verificationContext(for: run.id))
        ))
    }
}

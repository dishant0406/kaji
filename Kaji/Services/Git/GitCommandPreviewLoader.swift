import Foundation

enum GitCommandPreviewLoader {
    static func load(
        request: GitCommandRequest,
        presentation: GitCommandPresentation,
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String
    ) async -> GitCommandPreviewResult {
        let key = GitCommandPreviewKey(worktreePath: worktreePath, displayCommand: request.displayCommand)
        let git = GitRepositoryService()
        switch presentation {
        case .branchList:
            let branches = await (try? git.listBranches(repoPath: worktreePath)) ?? []
            return result(key: key, request: request, presentation: presentation, branches: branches)
        case .commitLog:
            let commits = await (try? git.commitLog(repoPath: worktreePath, maxCount: 60, skip: 0)) ?? []
            return result(key: key, request: request, presentation: presentation, commits: commits)
        case .statusList:
            let files = await (try? git.changedFiles(repoPath: worktreePath)) ?? []
            return result(
                key: key,
                request: request,
                presentation: presentation,
                files: diffPaletteFiles(
                    files: files,
                    projectID: projectID,
                    worktreeID: worktreeID,
                    worktreePath: worktreePath
                )
            )
        case .plainOutput:
            let output = await plainOutput(request: request, worktreePath: worktreePath)
            return result(key: key, request: request, presentation: presentation, output: output)
        }
    }

    private static func result(
        key: GitCommandPreviewKey,
        request: GitCommandRequest,
        presentation: GitCommandPresentation,
        commits: [GitCommit] = [],
        branches: [String] = [],
        files: [DiffPaletteFile] = [],
        output: String = ""
    ) -> GitCommandPreviewResult {
        GitCommandPreviewResult(
            key: key,
            request: request,
            presentation: presentation,
            commits: commits,
            branches: branches,
            files: files,
            output: output
        )
    }

    private static func plainOutput(request: GitCommandRequest, worktreePath: String) async -> String {
        guard let result = try? await GitProcessRunner.runGit(
            repoPath: worktreePath,
            arguments: request.arguments,
            lineLimit: 400
        )
        else {
            return "Failed to run \(request.displayCommand)."
        }
        let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined()
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func diffPaletteFiles(
        files: [GitStatusFile],
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String
    ) -> [DiffPaletteFile] {
        files.flatMap { file in
            var result: [DiffPaletteFile] = []
            if file.isStaged {
                result.append(DiffPaletteFile(
                    projectID: projectID,
                    worktreeID: worktreeID,
                    worktreePath: worktreePath,
                    file: file,
                    isStaged: true
                ))
            }
            if file.isUnstaged {
                result.append(DiffPaletteFile(
                    projectID: projectID,
                    worktreeID: worktreeID,
                    worktreePath: worktreePath,
                    file: file,
                    isStaged: false
                ))
            }
            return result
        }
    }
}

import Foundation

enum GitCommandPreviewStatus: Equatable {
    case idle
    case loading(GitCommandPreviewKey)
    case loaded(GitCommandPreviewResult)
    case failed(GitCommandPreviewKey, String)
}

struct GitCommandPreviewKey: Hashable {
    let worktreePath: String
    let displayCommand: String
}

struct GitCommandPreviewResult: Equatable {
    let key: GitCommandPreviewKey
    let request: GitCommandRequest
    let presentation: GitCommandPresentation
    let commits: [GitCommit]
    let branches: [String]
    let files: [DiffPaletteFile]
    let output: String

    static func empty(key: GitCommandPreviewKey, request: GitCommandRequest, presentation: GitCommandPresentation) -> Self {
        GitCommandPreviewResult(
            key: key,
            request: request,
            presentation: presentation,
            commits: [],
            branches: [],
            files: [],
            output: ""
        )
    }
}

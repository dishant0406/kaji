import Foundation

extension GitCommitInventoryBuilder {
    static func diffSnippets(
        repoPath: String,
        files: [GitStatusFile],
        inventoryFiles: [GitCommitInventoryFile]
    ) async -> [GitCommitDiffSnippet] {
        let byPath = Dictionary(uniqueKeysWithValues: inventoryFiles.map { ($0.path, $0) })
        let candidates = files.filter { file in
            guard let inventory = byPath[file.path] else { return false }
            return !inventory.isBinary && !inventory.isLowSignal && inventory.changeWeight <= 700
        }
        .sorted { lhs, rhs in
            (byPath[lhs.path]?.changeWeight ?? 0) > (byPath[rhs.path]?.changeWeight ?? 0)
        }
        .prefix(8)

        var snippets: [GitCommitDiffSnippet] = []
        var remainingCharacters = 12000
        let git = GitRepositoryService()

        for file in candidates where remainingCharacters > 0 {
            let hints = GitRepositoryService.DiffHints(
                hasStaged: file.isStaged,
                hasUnstaged: file.isUnstaged,
                isUntrackedOrNew: file.xStatus == "?" && file.yStatus == "?"
            )
            guard let diff = try? await git.patchAndCompare(
                repoPath: repoPath,
                filePath: file.path,
                lineLimit: 120,
                contextLineCount: 1,
                hints: hints
            )
            else { continue }
            let text = diff.rows.prefix(80).map(\.text).joined(separator: "\n")
            guard !text.isEmpty else { continue }
            let clipped = String(text.prefix(remainingCharacters))
            snippets.append(GitCommitDiffSnippet(
                path: file.path,
                text: clipped,
                truncated: diff.truncated || clipped.count < text.count
            ))
            remainingCharacters -= clipped.count
        }

        return snippets
    }
}

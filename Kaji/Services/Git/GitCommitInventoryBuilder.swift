import Foundation

enum GitCommitInventoryBuilder {
    static func build(
        repoPath: String,
        files: [GitStatusFile],
        selectedPaths: Set<String>,
        includeSnippets: Bool = true
    ) async -> GitCommitInventory {
        await build(
            repoPath: repoPath,
            files: files,
            selectedPaths: selectedPaths,
            snippetPolicy: includeSnippets ? GitCommitMessageContextLevel.medium.snippetPolicy : nil
        )
    }

    static func build(
        repoPath: String,
        files: [GitStatusFile],
        selectedPaths: Set<String>,
        snippetPolicy: GitCommitSnippetPolicy?
    ) async -> GitCommitInventory {
        let selected = files.filter { selectedPaths.contains($0.path) }
        let inventoryFiles = selected.map(inventoryFile)
        let snippets: [GitCommitDiffSnippet] = if let snippetPolicy {
            await diffSnippets(
                repoPath: repoPath,
                files: selected,
                inventoryFiles: inventoryFiles,
                policy: snippetPolicy
            )
        } else {
            []
        }
        return GitCommitInventory(
            files: inventoryFiles,
            totalAdditions: inventoryFiles.reduce(0) { $0 + $1.additions },
            totalDeletions: inventoryFiles.reduce(0) { $0 + $1.deletions },
            directoryGroups: directoryGroups(inventoryFiles),
            largestFiles: Array(inventoryFiles.sorted { $0.changeWeight > $1.changeWeight }.prefix(12)),
            lowSignalFiles: inventoryFiles.filter(\.isLowSignal),
            snippets: snippets,
            snippetsTruncated: snippets.contains(where: \.truncated)
        )
    }

    private static func inventoryFile(_ file: GitStatusFile) -> GitCommitInventoryFile {
        GitCommitInventoryFile(
            path: file.path,
            oldPath: file.oldPath,
            status: file.paletteStatusText,
            isStaged: file.isStaged,
            isUnstaged: file.isUnstaged,
            additions: file.additions ?? 0,
            deletions: file.deletions ?? 0,
            isBinary: file.isBinary,
            isLowSignal: isLowSignal(file.path)
        )
    }

    private static func directoryGroups(_ files: [GitCommitInventoryFile]) -> [GitCommitDirectoryGroup] {
        let grouped = Dictionary(grouping: files) { directoryScope($0.path) }
        return grouped.map { key, files in
            GitCommitDirectoryGroup(
                path: key,
                fileCount: files.count,
                additions: files.reduce(0) { $0 + $1.additions },
                deletions: files.reduce(0) { $0 + $1.deletions }
            )
        }
        .sorted { lhs, rhs in
            if lhs.fileCount != rhs.fileCount {
                return lhs.fileCount > rhs.fileCount
            }
            return lhs.path < rhs.path
        }
    }

    private static func directoryScope(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return "." }
        return parts.prefix(min(3, parts.count - 1)).joined(separator: "/")
    }

    private static func isLowSignal(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".lock") || lower.hasSuffix("package-lock.json") || lower.hasSuffix("pnpm-lock.yaml")
            || lower.hasSuffix("yarn.lock") || lower.hasSuffix("package.resolved") || lower.contains("/generated/")
            || lower.contains("/build/") || lower.contains("/dist/")
    }
}

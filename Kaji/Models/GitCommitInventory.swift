import Foundation

struct GitCommitInventory: Hashable {
    let files: [GitCommitInventoryFile]
    let totalAdditions: Int
    let totalDeletions: Int
    let directoryGroups: [GitCommitDirectoryGroup]
    let largestFiles: [GitCommitInventoryFile]
    let lowSignalFiles: [GitCommitInventoryFile]
    let snippets: [GitCommitDiffSnippet]
    let snippetsTruncated: Bool

    var fileCount: Int { files.count }
}

struct GitCommitInventoryFile: Hashable {
    let path: String
    let oldPath: String?
    let status: String
    let isStaged: Bool
    let isUnstaged: Bool
    let additions: Int
    let deletions: Int
    let isBinary: Bool
    let isLowSignal: Bool

    var changeWeight: Int {
        additions + deletions
    }
}

struct GitCommitDirectoryGroup: Hashable {
    let path: String
    let fileCount: Int
    let additions: Int
    let deletions: Int
}

struct GitCommitDiffSnippet: Hashable {
    let path: String
    let text: String
    let truncated: Bool
}

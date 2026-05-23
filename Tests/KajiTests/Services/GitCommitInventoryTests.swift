import Testing

@testable import Kaji

struct GitCommitInventoryTests {
    @Test
    func inventoryIncludesEverySelectedFileMetadata() async {
        let files = [
            file("Kaji/Views/CommitView.swift", additions: 10, deletions: 2),
            file("Package.resolved", additions: 100, deletions: 90),
            file("README.md", additions: 1, deletions: 0),
        ]

        let inventory = await GitCommitInventoryBuilder.build(
            repoPath: "/tmp",
            files: files,
            selectedPaths: Set(files.map(\.path)),
            includeSnippets: false
        )

        #expect(inventory.fileCount == 3)
        #expect(inventory.totalAdditions == 111)
        #expect(inventory.totalDeletions == 92)
        #expect(inventory.files.map(\.path).contains("Package.resolved"))
        #expect(inventory.lowSignalFiles.map(\.path) == ["Package.resolved"])
    }

    @Test
    func nativeDraftUsesCompleteInventoryScope() async {
        let files = [
            file("Kaji/Services/Git/CommitMessage.swift", additions: 20, deletions: 1),
            file("Kaji/Services/Git/Inventory.swift", additions: 30, deletions: 3),
        ]
        let inventory = await GitCommitInventoryBuilder.build(
            repoPath: "/tmp",
            files: files,
            selectedPaths: Set(files.map(\.path)),
            includeSnippets: false
        )

        #expect(GitCommitNativeDraft.message(for: inventory) == "Update Kaji Services Git")
        #expect(GitCommitNativeDraft.summary(for: inventory).contains("2 files changed"))
    }

    private func file(_ path: String, additions: Int, deletions: Int) -> GitStatusFile {
        GitStatusFile(
            path: path,
            oldPath: nil,
            xStatus: "M",
            yStatus: " ",
            additions: additions,
            deletions: deletions,
            isBinary: false
        )
    }
}

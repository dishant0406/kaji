import Testing

@testable import Kaji

struct GitCommitMessageAgentPromptTests {
    @Test
    func promptIncludesCompleteInventoryAndNativeDraft() {
        let inventory = GitCommitInventory(
            files: [
                GitCommitInventoryFile(
                    path: "A.swift",
                    oldPath: nil,
                    status: "M",
                    isStaged: true,
                    isUnstaged: false,
                    additions: 1,
                    deletions: 2,
                    isBinary: false,
                    isLowSignal: false
                ),
                GitCommitInventoryFile(
                    path: "B.swift",
                    oldPath: nil,
                    status: "A",
                    isStaged: false,
                    isUnstaged: true,
                    additions: 3,
                    deletions: 0,
                    isBinary: false,
                    isLowSignal: false
                ),
            ],
            totalAdditions: 4,
            totalDeletions: 2,
            directoryGroups: [GitCommitDirectoryGroup(path: ".", fileCount: 2, additions: 4, deletions: 2)],
            largestFiles: [],
            lowSignalFiles: [],
            snippets: [],
            snippetsTruncated: false
        )

        let prompt = GitCommitMessageAgentPrompt.make(.init(
            projectName: "Kaji",
            repoPath: "/repo",
            inventory: inventory,
            nativeDraft: "Update project changes"
        ))

        #expect(prompt.contains("Native draft: Update project changes"))
        #expect(prompt.contains("Answer immediately from the inventory below."))
        #expect(prompt.contains("Do not call tools"))
        #expect(prompt.contains("- M A.swift"))
        #expect(prompt.contains("- A B.swift"))
    }
}

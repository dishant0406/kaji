import Foundation
import Testing

@testable import Kaji

struct AgentChangedFilesSnapshotPolicyTests {
    @Test
    func ignoresGeneratedDependencyFoldersFromCatalog() {
        let policy = AgentChangedFilesSnapshotPolicy(maxStoredFiles: 10)
        let files = [
            changedFile("Kaji/App.swift"),
            changedFile("SomeFeature/node_modules/pkg/index.js"),
            changedFile(".build/debug/Kaji"),
            changedFile("Sources/Feature.swift"),
        ]

        let captured = policy.capturedFiles(from: files)

        #expect(captured.map(\.path) == ["Kaji/App.swift", "Sources/Feature.swift"])
    }

    @Test
    func capsStoredFiles() {
        let policy = AgentChangedFilesSnapshotPolicy(ignoreClassifier: nil, maxStoredFiles: 2)
        let files = (0 ..< 5).map { changedFile("Sources/File\($0).swift") }

        let captured = policy.capturedFiles(from: files)

        #expect(captured.map(\.path) == ["Sources/File0.swift", "Sources/File1.swift"])
    }

    private func changedFile(_ path: String) -> AgentChangedFile {
        AgentChangedFile(
            path: path,
            oldPath: nil,
            status: .modified,
            additions: 1,
            deletions: 0,
            isBinary: false
        )
    }
}

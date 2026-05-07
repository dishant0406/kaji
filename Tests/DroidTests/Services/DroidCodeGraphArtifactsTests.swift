import Foundation
import Testing

@testable import Droid

@Suite("DroidCodeGraphArtifacts", .serialized)
struct DroidCodeGraphArtifactsTests {
    @Test("delete removes generated project graph artifacts")
    func deleteRemovesProjectDirectory() throws {
        let tempRoot = makeTempRoot()
        DroidCodeGraphEnvironmentTestLock.lock()
        let previous = currentExtensionsDirectory
        setenv("DROID_EXTENSIONS_DIR", tempRoot.path, 1)
        defer {
            restoreExtensionsDirectory(previous)
            try? FileManager.default.removeItem(at: tempRoot)
            DroidCodeGraphEnvironmentTestLock.unlock()
        }

        let projectID = UUID()
        let worktreeID = UUID()
        let directory = DroidCodeGraphDirectory.projectDirectory(projectID: projectID, worktreeID: worktreeID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("droid-graph.json"))

        try DroidCodeGraphArtifacts.delete(projectID: projectID, worktreeID: worktreeID)

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("delete is a no-op when no graph artifacts exist")
    func deleteMissingDirectoryDoesNothing() throws {
        let tempRoot = makeTempRoot()
        DroidCodeGraphEnvironmentTestLock.lock()
        let previous = currentExtensionsDirectory
        setenv("DROID_EXTENSIONS_DIR", tempRoot.path, 1)
        defer {
            restoreExtensionsDirectory(previous)
            try? FileManager.default.removeItem(at: tempRoot)
            DroidCodeGraphEnvironmentTestLock.unlock()
        }

        try DroidCodeGraphArtifacts.delete(projectID: UUID(), worktreeID: UUID())
    }

    private var currentExtensionsDirectory: String? {
        guard let value = getenv("DROID_EXTENSIONS_DIR") else { return nil }
        return String(cString: value)
    }

    private func restoreExtensionsDirectory(_ value: String?) {
        if let value {
            setenv("DROID_EXTENSIONS_DIR", value, 1)
        } else {
            unsetenv("DROID_EXTENSIONS_DIR")
        }
    }

    private func makeTempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("droid-codegraph-artifacts-\(UUID().uuidString)", isDirectory: true)
    }
}

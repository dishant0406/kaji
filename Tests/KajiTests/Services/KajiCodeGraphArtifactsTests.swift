import Foundation
import Testing

@testable import Kaji

@Suite("KajiCodeGraphArtifacts", .serialized)
struct KajiCodeGraphArtifactsTests {
    @Test("delete removes generated project graph artifacts")
    func deleteRemovesProjectDirectory() throws {
        let tempRoot = makeTempRoot()
        KajiCodeGraphEnvironmentTestLock.lock()
        let previous = currentExtensionsDirectory
        setenv("KAJI_EXTENSIONS_DIR", tempRoot.path, 1)
        defer {
            restoreExtensionsDirectory(previous)
            try? FileManager.default.removeItem(at: tempRoot)
            KajiCodeGraphEnvironmentTestLock.unlock()
        }

        let projectID = UUID()
        let worktreeID = UUID()
        let directory = KajiCodeGraphDirectory.projectDirectory(projectID: projectID, worktreeID: worktreeID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("kaji-graph.json"))

        try KajiCodeGraphArtifacts.delete(projectID: projectID, worktreeID: worktreeID)

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("delete is a no-op when no graph artifacts exist")
    func deleteMissingDirectoryDoesNothing() throws {
        let tempRoot = makeTempRoot()
        KajiCodeGraphEnvironmentTestLock.lock()
        let previous = currentExtensionsDirectory
        setenv("KAJI_EXTENSIONS_DIR", tempRoot.path, 1)
        defer {
            restoreExtensionsDirectory(previous)
            try? FileManager.default.removeItem(at: tempRoot)
            KajiCodeGraphEnvironmentTestLock.unlock()
        }

        try KajiCodeGraphArtifacts.delete(projectID: UUID(), worktreeID: UUID())
    }

    private var currentExtensionsDirectory: String? {
        guard let value = getenv("KAJI_EXTENSIONS_DIR") else { return nil }
        return String(cString: value)
    }

    private func restoreExtensionsDirectory(_ value: String?) {
        if let value {
            setenv("KAJI_EXTENSIONS_DIR", value, 1)
        } else {
            unsetenv("KAJI_EXTENSIONS_DIR")
        }
    }

    private func makeTempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kaji-codegraph-artifacts-\(UUID().uuidString)", isDirectory: true)
    }
}

import Foundation
import Testing

@testable import Kaji

@Suite("KajiCodeGraphDirectory", .serialized)
struct KajiCodeGraphDirectoryTests {
    @Test
    func extensionRootUsesEnvironmentOverride() {
        let override = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        KajiCodeGraphEnvironmentTestLock.lock()
        setenv("KAJI_EXTENSIONS_DIR", override.path, 1)
        defer {
            unsetenv("KAJI_EXTENSIONS_DIR")
            try? FileManager.default.removeItem(at: override)
            KajiCodeGraphEnvironmentTestLock.unlock()
        }

        #expect(KajiCodeGraphDirectory.root.path == override.appendingPathComponent("kajicodegraph").path)
        #expect(KajiCodeGraphDirectory.graphify.lastPathComponent == "graphify")
        #expect(KajiCodeGraphDirectory.python.path.hasSuffix(".venv/bin/python"))

        let projectID = UUID()
        let worktreeID = UUID()
        let versions = KajiCodeGraphDirectory.graphVersionsDirectory(projectID: projectID, worktreeID: worktreeID)
        #expect(versions.path.contains(projectID.uuidString))
        #expect(versions.path.contains(worktreeID.uuidString))
        #expect(KajiCodeGraphDirectory.graphVersionDirectory(
            projectID: projectID,
            worktreeID: worktreeID,
            versionID: "abc123"
        ).lastPathComponent == "abc123")
        #expect(KajiCodeGraphDirectory.graphVersionsIndex(projectID: projectID, worktreeID: worktreeID).lastPathComponent == "index.json")
    }
}

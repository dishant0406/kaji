import Foundation
import Testing

@testable import Droid

@Suite("DroidCodeGraphDirectory", .serialized)
struct DroidCodeGraphDirectoryTests {
    @Test
    func extensionRootUsesEnvironmentOverride() {
        let override = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        DroidCodeGraphEnvironmentTestLock.lock()
        setenv("DROID_EXTENSIONS_DIR", override.path, 1)
        defer {
            unsetenv("DROID_EXTENSIONS_DIR")
            try? FileManager.default.removeItem(at: override)
            DroidCodeGraphEnvironmentTestLock.unlock()
        }

        #expect(DroidCodeGraphDirectory.root.path == override.appendingPathComponent("droidcodegraph").path)
        #expect(DroidCodeGraphDirectory.graphify.lastPathComponent == "graphify")
        #expect(DroidCodeGraphDirectory.python.path.hasSuffix(".venv/bin/python"))

        let projectID = UUID()
        let worktreeID = UUID()
        let versions = DroidCodeGraphDirectory.graphVersionsDirectory(projectID: projectID, worktreeID: worktreeID)
        #expect(versions.path.contains(projectID.uuidString))
        #expect(versions.path.contains(worktreeID.uuidString))
        #expect(DroidCodeGraphDirectory.graphVersionDirectory(
            projectID: projectID,
            worktreeID: worktreeID,
            versionID: "abc123"
        ).lastPathComponent == "abc123")
        #expect(DroidCodeGraphDirectory.graphVersionsIndex(projectID: projectID, worktreeID: worktreeID).lastPathComponent == "index.json")
    }
}

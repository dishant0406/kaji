import Foundation
import Testing

@testable import Droid

@MainActor
struct DroidCodeGraphInstructionsTests {
    @Test
    func createsEditableAgentsFileWithoutOverwritingUserChanges() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        setenv("DROID_EXTENSIONS_DIR", root.path, 1)
        defer {
            unsetenv("DROID_EXTENSIONS_DIR")
            try? fileManager.removeItem(at: root)
        }

        let store = DroidCodeGraphStore(fileURL: DroidCodeGraphDirectory.stateFile)
        let projectID = UUID()
        let worktreeID = UUID()
        let graph = DroidCodeGraphRuntime.shared.droidGraphURL(projectID: projectID, worktreeID: worktreeID)
        let python = DroidCodeGraphDirectory.python
        try fileManager.createDirectory(at: graph.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".data(using: .utf8)?.write(to: graph)
        try "#!/bin/sh\n".data(using: .utf8)?.write(to: python)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: python.path)
        store.markInstalled(commit: "test", message: nil)

        let file = try #require(DroidCodeGraphInstructions.ensureFile(
            projectID: projectID,
            worktreeID: worktreeID,
            store: store,
            fileManager: fileManager
        ))
        let initial = try String(contentsOf: file, encoding: .utf8)
        #expect(initial.contains("Droid Project Instructions"))
        #expect(initial.contains("droid-graph.json"))

        let claudeBridge = try #require(DroidCodeGraphInstructions.ensureClaudeBridge(
            projectID: projectID,
            worktreeID: worktreeID,
            fileManager: fileManager
        ))
        let claudeText = try String(contentsOf: claudeBridge, encoding: .utf8)
        #expect(claudeText.contains("@instructions/AGENTS.md"))

        let openCodeConfig = try #require(DroidCodeGraphInstructions.ensureOpenCodeConfig(
            projectID: projectID,
            worktreeID: worktreeID,
            instructionFile: file,
            fileManager: fileManager
        ))
        let openCodeText = try String(contentsOf: openCodeConfig, encoding: .utf8)
        #expect(openCodeText.contains("\"instructions\""))
        #expect(openCodeText.contains("AGENTS.md"))

        try "custom user rule\n".data(using: .utf8)?.write(to: file)
        _ = DroidCodeGraphInstructions.ensureFile(
            projectID: projectID,
            worktreeID: worktreeID,
            store: store,
            fileManager: fileManager
        )

        let updated = try String(contentsOf: file, encoding: .utf8)
        #expect(updated == "custom user rule\n")
    }
}

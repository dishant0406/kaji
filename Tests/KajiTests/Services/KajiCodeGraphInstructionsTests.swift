import Foundation
import Testing

@testable import Kaji

@MainActor
@Suite(.serialized)
struct KajiCodeGraphInstructionsTests {
    @Test
    func createsEditableAgentsFileWithoutOverwritingUserChanges() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        KajiCodeGraphEnvironmentTestLock.lock()
        setenv("KAJI_EXTENSIONS_DIR", root.path, 1)
        defer {
            unsetenv("KAJI_EXTENSIONS_DIR")
            try? fileManager.removeItem(at: root)
            KajiCodeGraphEnvironmentTestLock.unlock()
        }

        let store = KajiCodeGraphStore(fileURL: KajiCodeGraphDirectory.stateFile)
        let projectID = UUID()
        let worktreeID = UUID()
        let graph = KajiCodeGraphRuntime.shared.kajiGraphURL(projectID: projectID, worktreeID: worktreeID)
        let python = KajiCodeGraphDirectory.python
        try fileManager.createDirectory(at: graph.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".data(using: .utf8)?.write(to: graph)
        try "#!/bin/sh\n".data(using: .utf8)?.write(to: python)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: python.path)
        store.markInstalled(commit: "test", message: nil)

        let file = try #require(KajiCodeGraphInstructions.ensureFile(
            projectID: projectID,
            worktreeID: worktreeID,
            store: store,
            fileManager: fileManager
        ))
        let initial = try String(contentsOf: file, encoding: .utf8)
        #expect(initial.contains("Kaji Project Instructions"))
        #expect(initial.contains("kaji-graph.json"))

        let claudeBridge = try #require(KajiCodeGraphInstructions.ensureClaudeBridge(
            projectID: projectID,
            worktreeID: worktreeID,
            store: store,
            fileManager: fileManager
        ))
        let claudeText = try String(contentsOf: claudeBridge, encoding: .utf8)
        #expect(claudeText.contains("@instructions/AGENTS.md"))

        let codexBridge = try #require(KajiCodeGraphInstructions.ensureCodexBridge(
            projectID: projectID,
            worktreeID: worktreeID,
            store: store,
            fileManager: fileManager
        ))
        let codexText = try String(contentsOf: codexBridge, encoding: .utf8)
        #expect(codexText.contains("Read instructions/AGENTS.md"))

        let openCodeConfig = try #require(KajiCodeGraphInstructions.ensureOpenCodeConfig(
            projectID: projectID,
            worktreeID: worktreeID,
            instructionFile: file,
            store: store,
            fileManager: fileManager
        ))
        let openCodeText = try String(contentsOf: openCodeConfig, encoding: .utf8)
        #expect(openCodeText.contains("\"instructions\""))
        #expect(openCodeText.contains("AGENTS.md"))
        #expect(!openCodeText.contains("kaji-browser"))


        let descriptor = KajiBrowserMCPServerDescriptor(
            name: "kaji-browser",
            command: "/tmp/kaji-browser-mcp",
            arguments: [],
            environment: ["KAJI_BROWSER_BROKER_URL": "http://127.0.0.1:1"]
        )
        let openCodeBrowserConfig = try #require(KajiCodeGraphInstructions.ensureOpenCodeConfig(
            projectID: projectID,
            worktreeID: worktreeID,
            instructionFile: file,
            browserDescriptor: descriptor,
            store: store,
            fileManager: fileManager
        ))
        let openCodeBrowserText = try String(contentsOf: openCodeBrowserConfig, encoding: .utf8)
        #expect(openCodeBrowserText.contains("kaji-browser"))
        #expect(openCodeBrowserText.contains("KAJI_BROWSER_BROKER_URL"))
        let environment = Dictionary(uniqueKeysWithValues: KajiCodeGraphInstructions.environment(
            projectID: projectID,
            worktreeID: worktreeID,
            store: store,
            fileManager: fileManager
        ).map { ($0.key, $0.value) })
        #expect(environment["KAJI_CODE_GRAPH_INSTRUCTIONS"] == file.path)
        #expect(environment["KAJI_CODE_GRAPH_JSON"] == graph.path)

        try "custom user rule\n".data(using: .utf8)?.write(to: file)
        _ = KajiCodeGraphInstructions.ensureFile(
            projectID: projectID,
            worktreeID: worktreeID,
            store: store,
            fileManager: fileManager
        )

        let updated = try String(contentsOf: file, encoding: .utf8)
        #expect(updated == "custom user rule\n")
    }
}

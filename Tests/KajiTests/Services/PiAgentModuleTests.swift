import Foundation
import Testing
@testable import Kaji

struct PiAgentModuleTests {
    @Test
    @MainActor
    func startupCommandUsesProviderModelAndPrompt() {
        let command = PiAgentModule().startupCommand(
            baseCommand: "pi",
            prompt: "fix tests",
            model: "openai/gpt-5.4"
        )

        #expect(command.contains("pi"))
        #expect(command.contains("--model openai/gpt-5.4"))
        #expect(command.hasSuffix("'fix tests'"))
    }

    @Test
    @MainActor
    func resumeCommandUsesSessionFlag() {
        let command = AskCommandDispatcher.resumeCommand(for: .pi, sessionID: "session-123", prompt: "continue")

        #expect(command.contains("--session session-123"))
        #expect(command.hasSuffix("continue"))
    }

    @Test
    func parsesModelListTableRows() {
        #expect(PiAgentModels.modelID(from: "openai-codex        gpt-5.4        272K 128K yes yes") == "openai-codex/gpt-5.4")
        #expect(PiAgentModels.modelID(from: "provider model context max-out thinking images") == nil)
        #expect(PiAgentModels.modelID(from: "") == nil)
    }

    @Test
    func readsSessionHistory() throws {
        let root = tempDirectory()
        let sessions = root.appendingPathComponent(".pi/agent/sessions/project", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("2026_session.jsonl")
        let lines = [
            #"{"type":"session","version":3,"id":"pi-session","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp/muxy"}"#,
            #"{"type":"message","id":"a","parentId":null,"timestamp":"2026-01-01T00:00:01Z","message":{"role":"user","content":"Fix the issue"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let options = PiAgentHistory.options(
            projectPath: "/tmp/muxy",
            query: "",
            limit: 10,
            env: ["HOME": root.path],
            fileManager: .default
        )

        #expect(options.count == 1)
        #expect(options[0].provider == .pi)
        #expect(options[0].sessionID == "pi-session")
        #expect(options[0].title == "Fix the issue")
    }

    @Test
    func installCopiesKajiExtension() throws {
        let fileManager = FileManager.default
        let root = tempDirectory()
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        let hookClient = scripts.appendingPathComponent("KajiHookClient")
        let extensionFile = scripts.appendingPathComponent("pi-kaji-extension.ts")
        try "hook\n".write(to: hookClient, atomically: true, encoding: .utf8)
        try "export default function () { send('pi_attention') }\n".write(to: extensionFile, atomically: true, encoding: .utf8)

        try PiAgentModule().install(hookClientPath: hookClient.path, homeDirectory: home.path, fileManager: fileManager)

        let installed = try String(contentsOfFile: PiAgentModule.extensionPaths(homeDirectory: home.path)[0], encoding: .utf8)
        #expect(installed.contains("pi_attention"))
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

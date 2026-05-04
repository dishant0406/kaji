import Foundation
import Testing
@testable import Droid

struct PiAgentModuleTests {
    @Test
    @MainActor
    func startupCommandUsesProviderModelAndPrompt() {
        let command = AskCommandDispatcher.startupCommand(
            for: .pi,
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

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

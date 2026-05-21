import Foundation
import Testing

@testable import Kaji

@Suite("ParentAgent runtime contract")
struct ParentAgentRuntimeContractTests {
    @Test("runtime exposes kaji_subagent and hides legacy child-agent tools")
    func bundledRuntimeUsesSubagentToolOnly() throws {
        let text = try bundledRuntimeText()

        #expect(text.contains("kaji_subagent"))
        #expect(!text.contains("kaji_spawn_agent"))
        #expect(!text.contains("kaji_send_prompt"))
        #expect(!text.contains("kaji_observe_agents"))
        #expect(!text.contains("kaji_sleep"))
        #expect(!text.contains("kaji_get_agent_status"))
        #expect(!text.contains("kaji_stop_agent"))
        #expect(!text.contains("kaji_resume_agent"))
    }

    @Test("runtime no longer routes events through activeTaskID")
    func bundledRuntimeDoesNotUseActiveTaskID() throws {
        let text = try bundledRuntimeText()

        #expect(!text.contains("activeTaskID"))
        #expect(text.contains("promptQueue"))
        #expect(text.contains("context.taskID"))
    }

    @Test("source runtime matches bundled subagent contract")
    func sourceRuntimeUsesSubagentToolOnly() throws {
        let text = try sourceRuntimeText()

        #expect(text.contains("kaji_subagent"))
        #expect(!text.contains("kaji_spawn_agent"))
        #expect(!text.contains("kaji_send_prompt"))
        #expect(!text.contains("kaji_observe_agents"))
        #expect(!text.contains("activeTaskID"))
    }

    @Test("runtime exposes scoped graph-agent tools")
    func runtimeExposesGraphAgentTools() throws {
        for text in [try bundledRuntimeText(), try sourceRuntimeText()] {
            #expect(text.contains("KAJI_PARENT_AGENT_MODE"))
            #expect(text.contains("graph_read_file"))
            #expect(text.contains("graph_write_file"))
            #expect(text.contains("graph_shell"))
            #expect(text.contains("Do not choose or spawn Codex"))
        }
    }

    private func bundledRuntimeText() throws -> String {
        let url = try #require(ParentAgentRuntimeLocator.bundledScriptURL())
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func sourceRuntimeText() throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("KajiParentAgentRuntime/src")
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "ts" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }
}

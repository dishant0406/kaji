import Foundation
import Testing

@testable import Droid

@Suite("ParentAgent runtime contract")
struct ParentAgentRuntimeContractTests {
    @Test("runtime exposes droid_subagent and hides legacy child-agent tools")
    func bundledRuntimeUsesSubagentToolOnly() throws {
        let text = try bundledRuntimeText()

        #expect(text.contains("droid_subagent"))
        #expect(!text.contains("droid_spawn_agent"))
        #expect(!text.contains("droid_send_prompt"))
        #expect(!text.contains("droid_observe_agents"))
        #expect(!text.contains("droid_sleep"))
        #expect(!text.contains("droid_get_agent_status"))
        #expect(!text.contains("droid_stop_agent"))
        #expect(!text.contains("droid_resume_agent"))
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

        #expect(text.contains("droid_subagent"))
        #expect(!text.contains("droid_spawn_agent"))
        #expect(!text.contains("droid_send_prompt"))
        #expect(!text.contains("droid_observe_agents"))
        #expect(!text.contains("activeTaskID"))
    }

    @Test("runtime exposes scoped graph-agent tools")
    func runtimeExposesGraphAgentTools() throws {
        for text in [try bundledRuntimeText(), try sourceRuntimeText()] {
            #expect(text.contains("DROID_PARENT_AGENT_MODE"))
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
            .appendingPathComponent("Vendor/pi-mono/packages/droid-agent/src/main.ts")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

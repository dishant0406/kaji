import Foundation
import Testing

@testable import Kaji

struct KajiCodeGraphAgentPromptTests {
    @Test
    func promptRequiresAgenticGraphifyFlowAndFinalizer() {
        let request = KajiCodeGraphRunRequest(
            projectID: UUID(),
            worktreeID: UUID(),
            projectPath: "/tmp/My App",
            mode: "build"
        )
        let output = URL(fileURLWithPath: "/tmp/kaji graph/out", isDirectory: true)
        let work = output.appendingPathComponent("agent-work", isDirectory: true)
        let prompt = KajiCodeGraphAgentPrompt.make(request: request, output: output, work: work, buildID: "build-1")

        #expect(prompt.contains("semantic extraction"))
        #expect(prompt.contains("Do not use the old AST-only shortcut"))
        #expect(prompt.contains("Do not choose or spawn Codex"))
        #expect(prompt.contains("The Graphify skill does not need to be installed as a slash command"))
        #expect(!prompt.contains("kajicodegraph_runner.py finalize"))
        #expect(prompt.contains("Kaji will finalize and import the graph automatically"))
        #expect(prompt.contains("Do not report that no Kaji finalizer command was provided"))
        #expect(prompt.contains("buildID build-1"))
        #expect(prompt.contains("Keep project files untouched"))
        #expect(prompt.contains("--out /tmp/kaji graph/out/agent-work"))
        #expect(prompt.contains("GRAPHIFY_OUT=/tmp/kaji graph/out/agent-work/graphify-out"))
        #expect(prompt.contains("Never run Graphify with its default output path"))
        #expect(prompt.contains("/tmp/My App/graphify-out"))
    }
}

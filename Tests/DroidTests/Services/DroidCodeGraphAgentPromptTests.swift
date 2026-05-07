import Foundation
import Testing

@testable import Droid

struct DroidCodeGraphAgentPromptTests {
    @Test
    func promptRequiresAgenticGraphifyFlowAndFinalizer() {
        let request = DroidCodeGraphRunRequest(
            projectID: UUID(),
            worktreeID: UUID(),
            projectPath: "/tmp/My App",
            mode: "build"
        )
        let output = URL(fileURLWithPath: "/tmp/droid graph/out", isDirectory: true)
        let work = output.appendingPathComponent("agent-work", isDirectory: true)
        let prompt = DroidCodeGraphAgentPrompt.make(request: request, output: output, work: work, buildID: "build-1")

        #expect(prompt.contains("semantic extraction"))
        #expect(prompt.contains("Do not use the old AST-only shortcut"))
        #expect(prompt.contains("Do not choose or spawn Codex"))
        #expect(prompt.contains("The Graphify skill does not need to be installed as a slash command"))
        #expect(!prompt.contains("droidcodegraph_runner.py finalize"))
        #expect(prompt.contains("Droid will finalize and import the graph automatically"))
        #expect(prompt.contains("Do not report that no Droid finalizer command was provided"))
        #expect(prompt.contains("buildID build-1"))
        #expect(prompt.contains("Keep project files untouched"))
        #expect(prompt.contains("--out /tmp/droid graph/out/agent-work"))
        #expect(prompt.contains("GRAPHIFY_OUT=/tmp/droid graph/out/agent-work/graphify-out"))
        #expect(prompt.contains("Never run Graphify with its default output path"))
        #expect(prompt.contains("/tmp/My App/graphify-out"))
    }
}

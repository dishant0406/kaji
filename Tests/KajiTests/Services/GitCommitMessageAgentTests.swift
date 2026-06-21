import Testing

@testable import Kaji

struct GitCommitMessageAgentTests {
    @MainActor
    @Test
    func runtimeCommandUsesKajiAgentCommitRPCAndSelectedModel() {
        let settings = GitCommitMessageSettingsSnapshot(
            modelSelector: "anthropic/claude-sonnet-4-5",
            providerID: "anthropic",
            modelID: "claude-sonnet-4-5",
            contextLevel: .medium,
            customInstructions: ""
        )

        let frame = GitCommitMessageRuntimeClient.commandFrame(settings: settings, prompt: "inventory")

        #expect(frame.type == "generate_commit_message")
        #expect(frame.provider == "anthropic")
        #expect(frame.modelId == "claude-sonnet-4-5")
        #expect(frame.promptMessage == "inventory")
    }

    @MainActor
    @Test
    func runtimeCommandFallsBackToCommitRoleWhenNoModelSelected() {
        let settings = GitCommitMessageSettingsSnapshot(
            modelSelector: "",
            providerID: "",
            modelID: "",
            contextLevel: .medium,
            customInstructions: ""
        )

        let frame = GitCommitMessageRuntimeClient.commandFrame(settings: settings, prompt: "inventory")

        #expect(frame.type == "generate_commit_message")
        #expect(frame.provider == nil)
        #expect(frame.modelId == nil)
    }
}

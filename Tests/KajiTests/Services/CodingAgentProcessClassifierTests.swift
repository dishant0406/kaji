import Testing

@testable import Kaji

struct CodingAgentProcessClassifierTests {
    @Test
    func matchesDirectExecutableName() {
        let match = classify(process(commandName: "codex", commandLine: "codex", parentPID: 20)).first

        #expect(match?.providerID == "codex")
        #expect(match?.suspicion == .detached)
    }

    @Test
    func matchesGenericRuntimeOnlyWithProviderMarker() {
        let plainNode = process(commandName: "node", commandLine: "node server.js", parentPID: 20)
        let opencodeNode = process(commandName: "node", commandLine: "node ~/.opencode/plugins/kaji.js", parentPID: 20)

        #expect(classify(plainNode).isEmpty)
        #expect(classify(opencodeNode).first?.providerID == "opencode")
    }

    @Test
    func matchesClaudePackageMarker() {
        let claudeNode = process(commandName: "node", commandLine: "node /x/node_modules/@anthropic-ai/claude-code/cli.js", parentPID: 20)

        #expect(classify(claudeNode).first?.providerID == "claude")
    }

    @Test
    func marksOrphanWhenParentIsLaunchd() {
        let match = classify(process(commandName: "opencode", commandLine: "opencode", parentPID: 1)).first

        #expect(match?.suspicion == .orphan)
    }

    @Test
    func marksActiveWhenProcessGroupIsActive() {
        let match = classify(
            process(commandName: "claude", commandLine: "claude", parentPID: 20, processGroupID: 900),
            activeProcessGroupIDs: [900]
        ).first

        #expect(match?.providerID == "claude")
        #expect(match?.suspicion == .active)
    }

    private func classify(
        _ process: CodingAgentProcessInfo,
        activeProcessGroupIDs: Set<Int32> = []
    ) -> [CodingAgentProcessMatch] {
        CodingAgentProcessClassifier.classify(
            processes: [process],
            definitions: CodingAgentRegistry.shared.definitions,
            activeProcessGroupIDs: activeProcessGroupIDs
        )
    }

    private func process(
        commandName: String,
        commandLine: String,
        parentPID: Int32,
        processGroupID: Int32 = 100
    ) -> CodingAgentProcessInfo {
        CodingAgentProcessInfo(
            pid: 100,
            parentPID: parentPID,
            processGroupID: processGroupID,
            state: "running",
            tty: "??",
            cpuPercent: 0,
            memoryBytes: 1024,
            threadCount: 1,
            commandName: commandName,
            executablePath: nil,
            commandLine: commandLine
        )
    }
}

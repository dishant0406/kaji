import Testing

@testable import Kaji

struct CodingAgentProcessAggregatorTests {
    @Test
    func groupsByProviderAndSortsOrphansFirst() {
        let groups = CodingAgentProcessAggregator.groups(from: [
            match(providerID: "codex", providerName: "Codex", suspicion: .active, cpu: 20),
            match(providerID: "opencode", providerName: "OpenCode", suspicion: .orphan, cpu: 1),
        ])

        #expect(groups.map(\.providerID) == ["opencode", "codex"])
        #expect(groups[0].orphanCount == 1)
    }

    @Test
    func sumsProviderResources() {
        let groups = CodingAgentProcessAggregator.groups(from: [
            match(providerID: "codex", providerName: "Codex", suspicion: .active, cpu: 2, memory: 10),
            match(providerID: "codex", providerName: "Codex", suspicion: .detached, cpu: 3, memory: 20),
        ])

        #expect(groups.first?.cpuPercent == 5)
        #expect(groups.first?.memoryBytes == 30)
    }

    private func match(
        providerID: String,
        providerName: String,
        suspicion: CodingAgentProcessSuspicion,
        cpu: Double,
        memory: UInt64 = 0
    ) -> CodingAgentProcessMatch {
        CodingAgentProcessMatch(
            process: CodingAgentProcessInfo(
                pid: Int32(cpu * 100 + Double(memory)),
                parentPID: 1,
                processGroupID: 1,
                state: "running",
                tty: "??",
                cpuPercent: cpu,
                memoryBytes: memory,
                threadCount: 1,
                commandName: providerID,
                executablePath: nil,
                commandLine: providerID
            ),
            providerID: providerID,
            providerName: providerName,
            providerIconName: providerID,
            providerKillPatterns: [providerID],
            suspicion: suspicion
        )
    }
}

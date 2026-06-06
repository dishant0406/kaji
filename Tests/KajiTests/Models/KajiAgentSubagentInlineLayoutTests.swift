import Testing

@testable import Kaji

struct KajiAgentSubagentInlineLayoutTests {
    @Test
    func summarizesStatuses() throws {
        let layout = try layout([
            agent("a", index: 0, status: "running"),
            agent("b", index: 1, status: "pending"),
            agent("c", index: 2, status: "completed"),
            agent("d", index: 3, status: "failed"),
            agent("e", index: 4, status: "aborted"),
        ])

        #expect(layout.summary == "2 running · 1 done · 2 failed")
    }

    @Test
    func capsInlineRowsAndReportsOverflow() throws {
        let layout = try layout([
            agent("a", index: 0, status: "failed"),
            agent("b", index: 1, status: "failed"),
            agent("c", index: 2, status: "failed"),
            agent("d", index: 3, status: "failed"),
        ])

        #expect(layout.inlineAgents.map(\.id) == ["a", "b", "c"])
        #expect(layout.overflowCount == 1)
        #expect(layout.hasOverflow)
    }

    @Test
    func prioritizesRunningAgentsBeforeCompletedAgents() throws {
        let layout = try layout([
            agent("done", index: 0, status: "completed"),
            agent("failed", index: 1, status: "failed"),
            agent("running", index: 2, status: "running"),
            agent("pending", index: 3, status: "pending"),
        ])

        #expect(layout.inlineAgents.map(\.id) == ["running", "pending", "failed"])
    }

    @Test
    func usesResultOnlyTaskDetails() throws {
        let details = try #require(KajiAgentTaskToolDetails(json: .object([
            "results": .array([
                .object([
                    "id": .string("r1"),
                    "index": .number(0),
                    "agent": .string("explore"),
                    "task": .string("Analyze"),
                    "exitCode": .number(1),
                ]),
            ]),
        ])))
        let layout = KajiAgentSubagentInlineLayout(details: details)

        #expect(layout.inlineAgents.first?.id == "r1")
        #expect(layout.inlineAgents.first?.status == "failed")
        #expect(layout.summary == "0 running · 0 done · 1 failed")
    }

    private func layout(_ agents: [KajiAgentJSONValue]) throws -> KajiAgentSubagentInlineLayout {
        let details = try #require(KajiAgentTaskToolDetails(json: .object(["progress": .array(agents)])))
        return KajiAgentSubagentInlineLayout(details: details)
    }

    private func agent(_ id: String, index: Int, status: String) -> KajiAgentJSONValue {
        .object([
            "id": .string(id),
            "index": .number(Double(index)),
            "agent": .string("explore"),
            "status": .string(status),
            "task": .string("Task \(id)"),
        ])
    }
}

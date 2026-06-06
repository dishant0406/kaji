import Testing

@testable import Kaji

struct KajiAgentSubagentModelsTests {
    @Test
    func resultFallbackPreservesFailureText() throws {
        let result = try #require(KajiAgentSubagentResult(json: .object([
            "id": .string("0-scout"),
            "index": .number(0),
            "agent": .string("explore"),
            "task": .string("Inspect files"),
            "exitCode": .number(1),
            "output": .string(""),
            "stderr": .string("ReferenceError: missing symbol"),
            "durationMs": .number(1000),
            "tokens": .number(0),
        ])))

        let progress = KajiAgentSubagentProgress(result: result)

        #expect(progress.status == "failed")
        #expect(progress.recentOutput.isEmpty)
        #expect(progress.failureText == "ReferenceError: missing symbol")
    }

    @Test
    func progressParsesFailureText() throws {
        let progress = try #require(KajiAgentSubagentProgress(json: .object([
            "id": .string("0-scout"),
            "index": .number(0),
            "agent": .string("explore"),
            "status": .string("failed"),
            "task": .string("Inspect files"),
            "failureText": .string("Startup failed"),
            "toolCount": .number(0),
            "tokens": .number(0),
            "durationMs": .number(1000),
            "cost": .number(0),
        ])))

        #expect(progress.failureText == "Startup failed")
    }
}

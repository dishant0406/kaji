import Testing

@testable import Kaji

struct KajiAgentRuntimeStateSnapshotTests {
    @Test
    func parsesRuntimeState() throws {
        let snapshot = try #require(KajiAgentRuntimeStateSnapshot(json: .object([
            "sessionId": .string("new-session"),
            "sessionID": .string("legacy-session"),
            "sessionFile": .string("/tmp/session.jsonl"),
            "messageCount": .number(12),
            "thinkingLevel": .string("high"),
            "queuedMessageCount": .number(3),
            "isStreaming": .bool(true),
            "model": .object([
                "provider": .string("openai"),
                "id": .string("gpt-5"),
            ]),
            "todoPhases": .array([
                .object([
                    "name": .string("Build"),
                    "tasks": .array([
                        .object([
                            "content": .string("Implement"),
                            "status": .string("in_progress"),
                            "notes": .array([.string("native")]),
                        ]),
                    ]),
                ]),
            ]),
        ])))

        #expect(snapshot.sessionID == "new-session")
        #expect(snapshot.sessionFile == "/tmp/session.jsonl")
        #expect(snapshot.messageCount == 12)
        #expect(snapshot.thinkingLevel == "high")
        #expect(snapshot.queuedMessageCount == 3)
        #expect(snapshot.isRunning == true)
        #expect(snapshot.modelLabel == "openai / gpt-5")
        #expect(snapshot.todoPhases?.first?.name == "Build")
        #expect(snapshot.todoPhases?.first?.tasks.first?.notes == ["native"])
    }

    @Test
    func fallsBackToLegacySessionID() throws {
        let snapshot = try #require(KajiAgentRuntimeStateSnapshot(json: .object([
            "sessionID": .string("legacy-session"),
        ])))

        #expect(snapshot.sessionID == "legacy-session")
    }

    @Test
    func modelLabelUsesStableFallbacks() {
        let label = KajiAgentRuntimeStateSnapshot.modelLabel(from: .object([:]))

        #expect(label == "provider / model")
    }

    @Test
    func ignoresNonObjectState() {
        let snapshot = KajiAgentRuntimeStateSnapshot(json: .string("bad"))

        #expect(snapshot == nil)
    }
}

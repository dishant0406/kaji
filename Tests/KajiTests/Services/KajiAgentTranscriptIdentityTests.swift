import Testing

@testable import Kaji

struct KajiAgentTranscriptIdentityTests {
    @Test
    func stableUUIDsRepeatForSameSeed() {
        let first = KajiAgentTranscriptIdentity.uuid("tool", "abc")
        let second = KajiAgentTranscriptIdentity.uuid("tool", "abc")
        let different = KajiAgentTranscriptIdentity.uuid("tool", "def")

        #expect(first == second)
        #expect(first != different)
    }

    @Test
    func restoredTranscriptKeepsStableMessageIDsAcrossParses() throws {
        let payload = KajiAgentJSONValue.object([
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .string("Build it"),
                ]),
                .object([
                    "role": .string("assistant"),
                    "content": .array([
                        .object(["type": .string("thinking"), "thinking": .string("Planning")]),
                        .object(["type": .string("text"), "text": .string("Done")]),
                        .object([
                            "type": .string("toolCall"),
                            "id": .string("tool-1"),
                            "name": .string("bash"),
                            "arguments": .object(["command": .string("swift test")]),
                        ]),
                    ]),
                ]),
                .object([
                    "role": .string("toolResult"),
                    "toolCallId": .string("tool-1"),
                    "toolName": .string("bash"),
                    "content": .string("ok"),
                ]),
            ]),
        ])

        let first = try #require(KajiAgentTranscriptRestorer.restore(from: payload))
        let second = try #require(KajiAgentTranscriptRestorer.restore(from: payload))

        #expect(first.turns.map(\.id) == second.turns.map(\.id))
        #expect(first.turns.flatMap(\.messages).map(\.id) == second.turns.flatMap(\.messages).map(\.id))
        #expect(first.turns.flatMap(\.toolGroups).map(\.id) == second.turns.flatMap(\.toolGroups).map(\.id))
    }

    @Test
    func restoredRepeatedToolCallIDsAcrossTurnsKeepDistinctMessageIDs() throws {
        let payload = KajiAgentJSONValue.object([
            "messages": .array([
                restoredUser("First"),
                restoredToolCall(id: "tool-1"),
                restoredToolResult(id: "tool-1"),
                restoredUser("Second"),
                restoredToolCall(id: "tool-1"),
                restoredToolResult(id: "tool-1"),
            ]),
        ])

        let restored = try #require(KajiAgentTranscriptRestorer.restore(from: payload))
        let ids = restored.turns.flatMap(\.toolGroups).flatMap(\.tools).map(\.id)

        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }

    private func restoredUser(_ text: String) -> KajiAgentJSONValue {
        .object(["role": .string("user"), "content": .string(text)])
    }

    private func restoredToolCall(id: String) -> KajiAgentJSONValue {
        .object([
            "role": .string("assistant"),
            "content": .array([
                .object([
                    "type": .string("toolCall"),
                    "id": .string(id),
                    "name": .string("bash"),
                ]),
            ]),
        ])
    }

    private func restoredToolResult(id: String) -> KajiAgentJSONValue {
        .object([
            "role": .string("toolResult"),
            "toolCallId": .string(id),
            "toolName": .string("bash"),
            "content": .string("ok"),
        ])
    }
}

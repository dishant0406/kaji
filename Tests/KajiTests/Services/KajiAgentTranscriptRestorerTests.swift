import Testing

@testable import Kaji

struct KajiAgentTranscriptRestorerTests {
    @Test
    func restoresTurnsAssistantBlocksAndToolResults() throws {
        let restoration = try #require(KajiAgentTranscriptRestorer.restore(from: .object([
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
                    "content": .string("ok\npassed"),
                ]),
            ]),
        ])))

        #expect(restoration.turns.count == 1)
        #expect(restoration.activeTurnID == restoration.turns.first?.id)
        #expect(restoration.turns[0].user?.detail == "Build it")
        #expect(restoration.turns[0].messages.map(\.kind) == [.user, .thinking, .assistant, .tool])

        guard case let .toolGroup(group) = restoration.turns[0].blocks.last else {
            Issue.record("Expected a tool group")
            return
        }
        #expect(group.tools.first?.title == "bash")
        #expect(group.tools.first?.detail == "2 lines")
        #expect(group.tools.first?.preview == "ok\npassed")
        #expect(group.tools.first?.isComplete == true)
    }

    @Test
    func restoresTodoPhasesFromTodoWriteResult() throws {
        let restoration = try #require(KajiAgentTranscriptRestorer.restore(from: .object([
            "messages": .array([
                .object([
                    "role": .string("toolResult"),
                    "toolCallId": .string("todo-1"),
                    "toolName": .string("todo_write"),
                    "details": .object([
                        "phases": .array([
                            .object([
                                "name": .string("Ship"),
                                "tasks": .array([
                                    .object([
                                        "content": .string("Verify"),
                                        "status": .string("completed"),
                                        "notes": .array([.string("green")]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ])))

        #expect(restoration.turns.count == 1)
        #expect(restoration.todoPhases?.first?.name == "Ship")
        #expect(restoration.todoPhases?.first?.tasks.first?.content == "Verify")
        #expect(restoration.todoPhases?.first?.tasks.first?.notes == ["green"])
    }

    @Test
    func skipsHiddenCustomMessagesAndKeepsProviderErrors() throws {
        let restoration = try #require(KajiAgentTranscriptRestorer.restore(from: .object([
            "messages": .array([
                .object([
                    "role": .string("custom"),
                    "display": .bool(false),
                    "content": .string("hidden"),
                ]),
                .object([
                    "role": .string("assistant"),
                    "content": .string(""),
                    "errorMessage": .string("rate limited"),
                ]),
            ]),
        ])))

        #expect(restoration.turns.count == 1)
        #expect(restoration.turns[0].messages.count == 1)
        #expect(restoration.turns[0].messages.first?.kind == .error)
        #expect(restoration.turns[0].messages.first?.detail == "rate limited")
    }
}

import Testing

@testable import Kaji

struct CodexSessionEventParserTests {
    @Test
    func interactiveTaskCompleteProducesCompletion() {
        var context = CodexSessionEventParser.FileContext()
        _ = CodexSessionEventParser.consume(
            line: #"{"type":"session_meta","payload":{"originator":"codex-tui","source":"cli","cwd":"/tmp/muxy"}}"#,
            context: &context
        )

        let completion = CodexSessionEventParser.consume(
            line: #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"Hello.\nWhat do you need done?"}}"#,
            context: &context
        )

        #expect(completion == .init(turnID: "turn-1", message: "Hello. What do you need done?", cwd: "/tmp/muxy"))
    }

    @Test
    func execTaskCompleteIsIgnored() {
        var context = CodexSessionEventParser.FileContext()
        _ = CodexSessionEventParser.consume(
            line: #"{"type":"session_meta","payload":{"originator":"codex_exec","source":"exec"}}"#,
            context: &context
        )

        let completion = CodexSessionEventParser.consume(
            line: #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"Hello."}}"#,
            context: &context
        )

        #expect(completion == nil)
    }

    @Test
    func emptyTaskCompleteFallsBackToDefaultMessage() {
        var context = CodexSessionEventParser.FileContext(originator: "Codex Desktop", source: "vscode")

        let completion = CodexSessionEventParser.consume(
            line: #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-2","last_agent_message":""}}"#,
            context: &context
        )

        #expect(completion == .init(turnID: "turn-2", message: "Turn completed"))
    }

    @Test
    func taskCompleteUsesLastFinalAgentMessageWhenPayloadMessageMissing() {
        var context = CodexSessionEventParser.FileContext(originator: "codex-tui", source: "cli")
        _ = CodexSessionEventParser.consume(
            line: #"{"type":"event_msg","payload":{"type":"agent_message","phase":"final_answer","message":"Long answer from Codex.\nSecond line."}}"#,
            context: &context
        )

        let completion = CodexSessionEventParser.consume(
            line: #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-3"}}"#,
            context: &context
        )

        #expect(completion == .init(turnID: "turn-3", message: "Long answer from Codex. Second line."))
    }

    @Test
    func taskCompleteUsesFinalAssistantResponseItemWhenPayloadMessageMissing() {
        var context = CodexSessionEventParser.FileContext(originator: "codex_cli_rs", source: "cli")
        _ = CodexSessionEventParser.consume(
            line: #"{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Done from response item."}]}}"#,
            context: &context
        )

        let completion = CodexSessionEventParser.consume(
            line: #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-4","last_agent_message":null}}"#,
            context: &context
        )

        #expect(completion == .init(turnID: "turn-4", message: "Done from response item."))
    }
}

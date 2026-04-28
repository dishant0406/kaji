import Testing

@testable import Droid

struct CodexSessionEventParserTests {
    @Test
    func interactiveTaskCompleteProducesCompletion() {
        var context = CodexSessionEventParser.FileContext()
        _ = CodexSessionEventParser.consume(
            line: #"{"type":"session_meta","payload":{"originator":"codex-tui","source":"cli"}}"#,
            context: &context
        )

        let completion = CodexSessionEventParser.consume(
            line: #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"Hello.\nWhat do you need done?"}}"#,
            context: &context
        )

        #expect(completion == .init(turnID: "turn-1", message: "Hello. What do you need done?"))
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
}

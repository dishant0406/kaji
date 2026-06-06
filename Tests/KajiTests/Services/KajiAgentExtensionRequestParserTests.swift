import Testing

@testable import Kaji

struct KajiAgentExtensionRequestParserTests {
    @Test
    func parsesConfirmQuestionWithFallbackTitle() {
        let actions = KajiAgentExtensionRequestParser.actions(for: KajiAgentRPCFrame(
            id: "q1",
            type: "extension_ui_request",
            method: "confirm",
            message: "Proceed?"
        ))

        #expect(actions == [.question(KajiAgentQuestion(
            id: "q1",
            title: "Proceed?",
            method: "confirm",
            options: ["Confirm", "Cancel"]
        ))])
    }

    @Test
    func parsesEditorQuestionMetadata() {
        let actions = KajiAgentExtensionRequestParser.actions(for: KajiAgentRPCFrame(
            id: "q2",
            type: "extension_ui_request",
            method: "editor",
            title: "Edit prompt",
            placeholder: "Type",
            allowEmpty: true,
            prefill: "draft",
            promptStyle: true,
            timeout: 4
        ))

        #expect(actions == [.question(KajiAgentQuestion(
            id: "q2",
            title: "Edit prompt",
            method: "editor",
            placeholder: "Type",
            prefill: "draft",
            promptStyle: true,
            allowEmpty: true,
            timeout: 4,
            options: []
        ))])
    }

    @Test
    func parsesOpenURLLoginDisplayAndSystemNotice() {
        let actions = KajiAgentExtensionRequestParser.actions(for: KajiAgentRPCFrame(
            id: "login",
            type: "extension_ui_request",
            method: "open_url",
            url: "https://example.com",
            instructions: "Enter code: AB12-CD34"
        ))

        #expect(actions == [
            .loginDisplay(KajiAgentLoginDisplay(
                url: "https://example.com",
                instructions: "Enter code: AB12-CD34",
                code: "AB12-CD34",
                status: "Enter code: AB12-CD34"
            )),
            .openURL("https://example.com"),
            .system(title: "Login", detail: "Enter code: AB12-CD34", kind: .event),
        ])
    }

    @Test
    func parsesNotifyError() {
        let actions = KajiAgentExtensionRequestParser.actions(for: KajiAgentRPCFrame(
            id: "n1",
            type: "extension_ui_request",
            method: "notify",
            message: "Failed",
            notifyType: "error"
        ))

        #expect(actions == [.system(title: "Error", detail: "Failed", kind: .error)])
    }

    @Test
    func ignoresMissingIdentity() {
        let actions = KajiAgentExtensionRequestParser.actions(for: KajiAgentRPCFrame(
            type: "extension_ui_request",
            method: "confirm"
        ))

        #expect(actions.isEmpty)
    }
}

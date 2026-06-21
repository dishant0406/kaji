import Testing

@testable import Kaji

struct KajiAgentToolRendererTests {
    @Test
    func rendersBashCommandAsPrimaryTitle() {
        let message = KajiAgentMessage(
            kind: .tool,
            title: "bash",
            detail: "",
            toolArguments: "{\"command\":\"swift test --filter KajiAgent\"}",
            isComplete: false
        )

        let descriptor = KajiAgentToolRenderer.descriptor(for: message)

        #expect(descriptor.iconName == "terminal")
        #expect(descriptor.title == "swift test --filter KajiAgent")
        #expect(descriptor.subtitle == "Running")
    }

    @Test
    func rendersEditFilePathAsPrimaryTitle() {
        let message = KajiAgentMessage(
            kind: .tool,
            title: "edit",
            detail: "",
            toolArguments: "{\"file_path\":\"Kaji/Services/KajiAgentStore.swift\"}",
            isComplete: true
        )

        let descriptor = KajiAgentToolRenderer.descriptor(for: message)

        #expect(descriptor.iconName == "square.and.pencil")
        #expect(descriptor.title == "Kaji/Services/KajiAgentStore.swift")
        #expect(descriptor.subtitle == "Completed")
    }
}

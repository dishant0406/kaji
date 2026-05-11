import Foundation
import Testing
@testable import Kaji

struct CodingAgentModelConfigTests {
    @Test
    func claudeUsesMostSpecificAvailableModels() throws {
        let root = tempDirectory()
        let project = root.appendingPathComponent("project", isDirectory: true)
        try writeJSON(["availableModels": ["user-model"]], to: root.appendingPathComponent(".claude/settings.json"))
        try writeJSON(["availableModels": ["project-model"]], to: project.appendingPathComponent(".claude/settings.json"))
        try writeJSON(["availableModels": ["local-model", "  "]], to: project.appendingPathComponent(".claude/settings.local.json"))

        let models = ClaudeCodeAgentModule.configuredModels(
            projectPath: project.path,
            env: ["HOME": root.path]
        )

        #expect(models == ["local-model"])
    }

    @Test
    func claudeFallsBackToUserAvailableModels() throws {
        let root = tempDirectory()
        try writeJSON(["availableModels": ["sonnet", "opus"]], to: root.appendingPathComponent(".claude/settings.json"))

        let models = ClaudeCodeAgentModule.configuredModels(projectPath: nil, env: ["HOME": root.path])

        #expect(models == ["sonnet", "opus"])
    }

    @Test
    func codexReadsConfiguredDefaultModel() throws {
        let root = tempDirectory()
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try "model = \"gpt-5.4\"\n".write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let model = CodexAgentModule.configuredDefaultModel(env: ["CODEX_HOME": codexHome.path])

        #expect(model == "gpt-5.4")
    }

    @Test
    func codexPrependsConfiguredModelWhenMissingFromFallbacks() throws {
        let root = tempDirectory()
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try "model = 'custom-model'\n".write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let models = CodexAgentModule.modelOptions(
            env: ["CODEX_HOME": codexHome.path],
            fallbackModels: ["gpt-5.5"]
        )

        #expect(models == ["custom-model", "gpt-5.5"])
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        try data.write(to: url)
    }
}

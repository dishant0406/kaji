import Foundation
import Testing

@testable import Kaji

@MainActor
struct CodingAgentShimTests {
    @Test
    func codexShimPreservesUserArgumentsAndAdditionalDirectories() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "codex", realEnv: "KAJI_REAL_CODEX", graphEnv: [
            "KAJI_CODE_GRAPH_PROJECT_DIR": "kaji-graph",
            "KAJI_CODE_GRAPH_ROOT_DIR": "kaji-root",
        ], args: ["--add-dir", "user-extra", "hello"])

        #expect(result == ["--add-dir", "kaji-graph", "--add-dir", "kaji-root", "--add-dir", "user-extra", "hello"])
    }



    @Test
    func codexShimResolvesGraphFromCurrentDirectory() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let graphRoot = root.appendingPathComponent("extensions/kajicodegraph", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let graphProject = graphRoot.appendingPathComponent("projects/project/worktree", isDirectory: true)
        let graphOutput = graphProject.appendingPathComponent("graphify-out", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: graphOutput, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: graphProject.appendingPathComponent("instructions", isDirectory: true), withIntermediateDirectories: true)
        try Data("{\"isEnabled\":true,\"phase\":\"installed\"}".utf8).write(to: graphRoot.appendingPathComponent("state.json"))
        try Data("{\"projectPath\":\"\(project.path)\"}".utf8).write(to: graphOutput.appendingPathComponent("kaji-graph.json"))
        try Data("graph instructions".utf8).write(to: graphProject.appendingPathComponent("instructions/AGENTS.md"))

        let result = try CodingAgentShimTestHarness.runShim(
            named: "codex",
            realEnv: "KAJI_REAL_CODEX",
            graphEnv: ["KAJI_CODE_GRAPH_ROOT_DIR": "extensions/kajicodegraph"],
            args: ["hello"],
            root: root,
            workingDirectory: project
        )

        #expect(result == [
            "-c",
            "model_instructions_file=\"extensions/kajicodegraph/projects/project/worktree/instructions/AGENTS.md\"",
            "--add-dir",
            "extensions/kajicodegraph/projects/project/worktree",
            "--add-dir",
            "extensions/kajicodegraph",
            "hello",
        ])
        #expect(fileManager.fileExists(atPath: graphProject.appendingPathComponent("AGENTS.md").path))
    }

    @Test
    func codexShimCreatesInstructionsForResolvedGraph() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let graphRoot = root.appendingPathComponent("extensions/kajicodegraph", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let graphProject = graphRoot.appendingPathComponent("projects/project/worktree", isDirectory: true)
        let graphOutput = graphProject.appendingPathComponent("graphify-out", isDirectory: true)
        let instructions = graphProject.appendingPathComponent("instructions/AGENTS.md")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: graphOutput, withIntermediateDirectories: true)
        try Data("{\"isEnabled\":true,\"phase\":\"installed\"}".utf8).write(to: graphRoot.appendingPathComponent("state.json"))
        try Data("{\"projectPath\":\"\(project.path)\"}".utf8).write(to: graphOutput.appendingPathComponent("kaji-graph.json"))

        let result = try CodingAgentShimTestHarness.runShim(
            named: "codex",
            realEnv: "KAJI_REAL_CODEX",
            graphEnv: ["KAJI_CODE_GRAPH_ROOT_DIR": "extensions/kajicodegraph"],
            args: ["hello"],
            root: root,
            workingDirectory: project
        )

        #expect(result == [
            "-c",
            "model_instructions_file=\"extensions/kajicodegraph/projects/project/worktree/instructions/AGENTS.md\"",
            "--add-dir",
            "extensions/kajicodegraph/projects/project/worktree",
            "--add-dir",
            "extensions/kajicodegraph",
            "hello",
        ])
        #expect(fileManager.fileExists(atPath: instructions.path))
    }

    @Test
    func piShimUsesNativeAppendSystemPrompt() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "pi", realEnv: "KAJI_REAL_PI", graphEnv: [
            "KAJI_CODE_GRAPH_INSTRUCTIONS": "instructions/AGENTS.md",
        ], args: ["hello"])

        #expect(result == ["--append-system-prompt", "instructions/AGENTS.md", "hello"])
    }



    @Test
    func claudeShimUsesNativeAdditionalDirectory() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "claude", realEnv: "KAJI_REAL_CLAUDE", graphEnv: [
            "KAJI_CODE_GRAPH_PROJECT_DIR": "kaji-graph",
            "KAJI_CODE_GRAPH_ROOT_DIR": "kaji-root",
        ], args: ["hello"])

        #expect(result == ["--add-dir", "kaji-graph", "--add-dir", "kaji-root", "hello"])
    }

    @Test
    func openCodeShimUsesNativeConfigEnvironment() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "opencode", realEnv: "KAJI_REAL_OPENCODE", graphEnv: [
            "KAJI_CODE_GRAPH_OPENCODE_CONFIG": "opencode.json",
        ], args: ["run", "hello"])

        #expect(result == ["OPENCODE_CONFIG=opencode.json", "run", "hello"])
    }


}

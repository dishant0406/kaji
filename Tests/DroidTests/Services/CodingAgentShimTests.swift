import Foundation
import Testing

@testable import Droid

@MainActor
struct CodingAgentShimTests {
    @Test
    func codexShimPreservesUserArgumentsAndAdditionalDirectories() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "codex", realEnv: "DROID_REAL_CODEX", graphEnv: [
            "DROID_CODE_GRAPH_PROJECT_DIR": "droid-graph",
            "DROID_CODE_GRAPH_ROOT_DIR": "droid-root",
        ], args: ["--add-dir", "user-extra", "hello"])

        #expect(result == ["--add-dir", "droid-graph", "--add-dir", "droid-root", "--add-dir", "user-extra", "hello"])
    }

    @Test
    func codexShimPrependsBrowserMCPArguments() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "codex", realEnv: "DROID_REAL_CODEX", graphEnv: [
            "DROID_CODEX_BROWSER_MCP_ARGS": "-c 'mcp_servers.droid-browser.command=\"/tmp/droid-browser-mcp\"'",
        ], args: ["hello"])

        #expect(result == [
            "-c",
            "mcp_servers.droid-browser.command=\"/tmp/droid-browser-mcp\"",
            "hello",
        ])
    }


    @Test
    func codexShimAddsInstalledBrowserMCPWithoutInjectedEnvironment() throws {
        let result = try CodingAgentShimTestHarness.runShim(
            named: "codex",
            realEnv: "DROID_REAL_CODEX",
            graphEnv: [:],
            args: ["hello"],
            installBrowserMCP: true
        )

        #expect(result == [
            "-c",
            "mcp_servers.droid-browser.command=\"home/.droid/bin/droid-browser-mcp\"",
            "-c",
            "mcp_servers.droid-browser.args=[]",
            "hello",
        ])
    }

    @Test
    func codexShimResolvesGraphFromCurrentDirectory() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let graphRoot = root.appendingPathComponent("extensions/droidcodegraph", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let graphProject = graphRoot.appendingPathComponent("projects/project/worktree", isDirectory: true)
        let graphOutput = graphProject.appendingPathComponent("graphify-out", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: graphOutput, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: graphProject.appendingPathComponent("instructions", isDirectory: true), withIntermediateDirectories: true)
        try Data("{\"isEnabled\":true,\"phase\":\"installed\"}".utf8).write(to: graphRoot.appendingPathComponent("state.json"))
        try Data("{\"projectPath\":\"\(project.path)\"}".utf8).write(to: graphOutput.appendingPathComponent("droid-graph.json"))
        try Data("graph instructions".utf8).write(to: graphProject.appendingPathComponent("instructions/AGENTS.md"))

        let result = try CodingAgentShimTestHarness.runShim(
            named: "codex",
            realEnv: "DROID_REAL_CODEX",
            graphEnv: ["DROID_CODE_GRAPH_ROOT_DIR": "extensions/droidcodegraph"],
            args: ["hello"],
            root: root,
            workingDirectory: project
        )

        #expect(result == [
            "-c",
            "model_instructions_file=\"extensions/droidcodegraph/projects/project/worktree/instructions/AGENTS.md\"",
            "--add-dir",
            "extensions/droidcodegraph/projects/project/worktree",
            "--add-dir",
            "extensions/droidcodegraph",
            "hello",
        ])
        #expect(fileManager.fileExists(atPath: graphProject.appendingPathComponent("AGENTS.md").path))
    }

    @Test
    func codexShimCreatesInstructionsForResolvedGraph() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let graphRoot = root.appendingPathComponent("extensions/droidcodegraph", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let graphProject = graphRoot.appendingPathComponent("projects/project/worktree", isDirectory: true)
        let graphOutput = graphProject.appendingPathComponent("graphify-out", isDirectory: true)
        let instructions = graphProject.appendingPathComponent("instructions/AGENTS.md")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: graphOutput, withIntermediateDirectories: true)
        try Data("{\"isEnabled\":true,\"phase\":\"installed\"}".utf8).write(to: graphRoot.appendingPathComponent("state.json"))
        try Data("{\"projectPath\":\"\(project.path)\"}".utf8).write(to: graphOutput.appendingPathComponent("droid-graph.json"))

        let result = try CodingAgentShimTestHarness.runShim(
            named: "codex",
            realEnv: "DROID_REAL_CODEX",
            graphEnv: ["DROID_CODE_GRAPH_ROOT_DIR": "extensions/droidcodegraph"],
            args: ["hello"],
            root: root,
            workingDirectory: project
        )

        #expect(result == [
            "-c",
            "model_instructions_file=\"extensions/droidcodegraph/projects/project/worktree/instructions/AGENTS.md\"",
            "--add-dir",
            "extensions/droidcodegraph/projects/project/worktree",
            "--add-dir",
            "extensions/droidcodegraph",
            "hello",
        ])
        #expect(fileManager.fileExists(atPath: instructions.path))
    }

    @Test
    func piShimUsesNativeAppendSystemPrompt() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "pi", realEnv: "DROID_REAL_PI", graphEnv: [
            "DROID_CODE_GRAPH_INSTRUCTIONS": "instructions/AGENTS.md",
        ], args: ["hello"])

        #expect(result == ["--append-system-prompt", "instructions/AGENTS.md", "hello"])
    }

    @Test
    func piShimPrependsBrowserMCPConfig() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "pi", realEnv: "DROID_REAL_PI", graphEnv: [
            "DROID_PI_BROWSER_MCP_CONFIG": "configs/pi-browser-mcp.json",
        ], args: ["hello"])

        #expect(result == ["--mcp-config", "configs/pi-browser-mcp.json", "hello"])
    }

    @Test
    func claudeShimPrependsBrowserMCPConfig() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "claude", realEnv: "DROID_REAL_CLAUDE", graphEnv: [
            "DROID_CLAUDE_BROWSER_MCP_CONFIG": "configs/claude-browser-mcp.json",
        ], args: ["hello"])

        #expect(result == ["--mcp-config", "configs/claude-browser-mcp.json", "hello"])
    }

    @Test
    func claudeShimUsesNativeAdditionalDirectory() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "claude", realEnv: "DROID_REAL_CLAUDE", graphEnv: [
            "DROID_CODE_GRAPH_PROJECT_DIR": "droid-graph",
            "DROID_CODE_GRAPH_ROOT_DIR": "droid-root",
        ], args: ["hello"])

        #expect(result == ["--add-dir", "droid-graph", "--add-dir", "droid-root", "hello"])
    }

    @Test
    func openCodeShimUsesNativeConfigEnvironment() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "opencode", realEnv: "DROID_REAL_OPENCODE", graphEnv: [
            "DROID_CODE_GRAPH_OPENCODE_CONFIG": "opencode.json",
        ], args: ["run", "hello"])

        #expect(result == ["OPENCODE_CONFIG=opencode.json", "run", "hello"])
    }

    @Test
    func openCodeShimUsesBrowserConfigWithoutCodeGraph() throws {
        let result = try CodingAgentShimTestHarness.runShim(named: "opencode", realEnv: "DROID_REAL_OPENCODE", graphEnv: [
            "DROID_OPENCODE_BROWSER_MCP_CONFIG": "configs/opencode-browser-mcp.json",
        ], args: ["run", "hello"])

        #expect(result == ["OPENCODE_CONFIG=configs/opencode-browser-mcp.json", "run", "hello"])
    }

}

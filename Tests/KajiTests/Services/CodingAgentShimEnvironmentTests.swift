import Foundation
import Testing

@testable import Kaji

@MainActor
struct CodingAgentShimEnvironmentTests {
    @Test
    func prependsShimsWhenCodeGraphIsEnabledAndProjectGraphExists() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.makeInstalledGraph()
        try fixture.executable("codex")

        let values = Dictionary(uniqueKeysWithValues: CodingAgentShimEnvironment.variables(
            projectID: fixture.projectID,
            worktreeID: fixture.worktreeID,
            environment: ["PATH": fixture.bin.path],
            homeDirectory: fixture.home.path,
            store: fixture.store,
            fileManager: fixture.fileManager,
            browserEnabled: true
        ).map { ($0.key, $0.value) })

        let shimDirectory = CodingAgentShimInstaller.directory(homeDirectory: fixture.home.path).path
        #expect(values["PATH"]?.hasPrefix(shimDirectory + ":") == true)
        #expect(values["KAJI_REAL_CODEX"] == fixture.bin.appendingPathComponent("codex").path)
        #expect(values["KAJI_AGENT_SHIM_DIR"] == shimDirectory)
        #expect(values["ZDOTDIR"] == KajiShellBootstrapInstaller.directory(homeDirectory: fixture.home.path).path)
        #expect(values["KAJI_BROWSER_MCP_COMMAND"] == "\(shimDirectory)/kaji-browser-mcp")
        #expect(values["KAJI_CODEX_BROWSER_MCP_ARGS"]?.contains("mcp_servers.kaji-browser.command") == true)
        #expect(values["KAJI_CLAUDE_BROWSER_MCP_CONFIG"]?.hasSuffix(".kaji/agent-configs/claude-browser-mcp.json") == true)
        #expect(values["KAJI_OPENCODE_BROWSER_MCP_CONFIG"]?.hasSuffix(".kaji/agent-configs/opencode-browser-mcp.json") == true)
        #expect(values["KAJI_PI_BROWSER_MCP_CONFIG"]?.hasSuffix(".kaji/agent-configs/pi-browser-mcp.json") == true)
    }

    @Test
    func skipsCodeGraphVarsWhenCodeGraphDisabled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.makeInstalledGraph()
        fixture.store.setEnabled(false)

        let values = CodingAgentShimEnvironment.variables(
            projectID: fixture.projectID,
            worktreeID: fixture.worktreeID,
            environment: ["PATH": fixture.bin.path],
            homeDirectory: fixture.home.path,
            store: fixture.store,
            fileManager: fixture.fileManager,
            browserEnabled: true
        )

        let keys = Set(values.map(\.key))
        #expect(keys.contains("KAJI_AGENT_SHIM_DIR"))
        #expect(!keys.contains("KAJI_CODE_GRAPH_INSTRUCTIONS"))
    }

    @Test
    func skipsCodeGraphVarsWhenProjectGraphIsMissing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.makeInstalledRuntime()

        let values = CodingAgentShimEnvironment.variables(
            projectID: fixture.projectID,
            worktreeID: fixture.worktreeID,
            environment: ["PATH": fixture.bin.path],
            homeDirectory: fixture.home.path,
            store: fixture.store,
            fileManager: fixture.fileManager,
            browserEnabled: true
        )

        let keys = Set(values.map(\.key))
        #expect(keys.contains("KAJI_AGENT_SHIM_DIR"))
        #expect(!keys.contains("KAJI_CODE_GRAPH_INSTRUCTIONS"))
    }
    @Test
    func resolvesLatestNvmExecutableBeforeStalePathVersion() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.makeInstalledRuntime()
        try fixture.executable("codex")
        let latest = try fixture.nvmExecutable(name: "codex", version: "v22.20.0")
        _ = try fixture.nvmExecutable(name: "codex", version: "v22.15.0")

        let values = Dictionary(uniqueKeysWithValues: CodingAgentShimEnvironment.variables(
            projectID: fixture.projectID,
            worktreeID: fixture.worktreeID,
            environment: ["PATH": fixture.bin.path],
            homeDirectory: fixture.home.path,
            store: fixture.store,
            fileManager: fixture.fileManager,
            browserEnabled: true
        ).map { ($0.key, $0.value) })

        #expect(values["KAJI_REAL_CODEX"] == latest.path)
    }

    @Test
    func skipsBrowserEnvironmentWhenBrowserDisabled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.makeInstalledRuntime()
        let staleConfig = fixture.home
            .appendingPathComponent(".kaji/agent-configs", isDirectory: true)
            .appendingPathComponent("claude-browser-mcp.json")
        try fixture.fileManager.createDirectory(at: staleConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: staleConfig)
        let staleSession = KajiBrowserSessionEnvironmentStore.fileURL(homeDirectory: fixture.home.path)
        try fixture.fileManager.createDirectory(at: staleSession.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: staleSession)

        let values = CodingAgentShimEnvironment.variables(
            projectID: fixture.projectID,
            worktreeID: fixture.worktreeID,
            environment: ["PATH": fixture.bin.path],
            homeDirectory: fixture.home.path,
            store: fixture.store,
            fileManager: fixture.fileManager,
            browserEnabled: false
        )

        let keys = Set(values.map(\.key))
        #expect(keys.contains("KAJI_AGENT_SHIM_DIR"))
        #expect(!keys.contains("KAJI_BROWSER_MCP_COMMAND"))
        #expect(!keys.contains("KAJI_CODEX_BROWSER_MCP_ARGS"))
        #expect(!fixture.fileManager.fileExists(atPath: staleConfig.path))
        #expect(!fixture.fileManager.fileExists(atPath: staleSession.path))
    }

}

@MainActor
private final class Fixture {
    let fileManager = FileManager.default
    let root: URL
    let bin: URL
    let home: URL
    let store: KajiCodeGraphStore
    let projectID = UUID()
    let worktreeID = UUID()

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        bin = root.appendingPathComponent("bin", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        let graphRoot = root.appendingPathComponent("kajicodegraph", isDirectory: true)
        store = KajiCodeGraphStore(fileURL: graphRoot.appendingPathComponent("state.json"))
        try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    func makeInstalledGraph() throws {
        try makeInstalledRuntime()
        let graph = store.kajiGraphURL(projectID: projectID, worktreeID: worktreeID)
        try fileManager.createDirectory(at: graph.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".data(using: .utf8)?.write(to: graph)
    }

    func makeInstalledRuntime() throws {
        let python = store.rootDirectory
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin/python")
        try fileManager.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".data(using: .utf8)?.write(to: python)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: python.path)
        store.markInstalled(commit: "test", message: nil)
    }

    func executable(_ name: String) throws {
        let path = bin.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }

    func nvmExecutable(name: String, version: String) throws -> URL {
        let path = home
            .appendingPathComponent(".nvm/versions/node", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(name)
        try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        return path
    }
}

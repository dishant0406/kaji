import Foundation
import Testing

@testable import Droid

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
            fileManager: fixture.fileManager
        ).map { ($0.key, $0.value) })

        let shimDirectory = CodingAgentShimInstaller.directory(homeDirectory: fixture.home.path).path
        #expect(values["PATH"]?.hasPrefix(shimDirectory + ":") == true)
        #expect(values["DROID_REAL_CODEX"] == fixture.bin.appendingPathComponent("codex").path)
        #expect(values["DROID_AGENT_SHIM_DIR"] == shimDirectory)
        #expect(values["ZDOTDIR"] == DroidShellBootstrapInstaller.directory(homeDirectory: fixture.home.path).path)
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
            fileManager: fixture.fileManager
        )

        let keys = Set(values.map(\.key))
        #expect(keys.contains("DROID_AGENT_SHIM_DIR"))
        #expect(!keys.contains("DROID_CODE_GRAPH_INSTRUCTIONS"))
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
            fileManager: fixture.fileManager
        )

        let keys = Set(values.map(\.key))
        #expect(keys.contains("DROID_AGENT_SHIM_DIR"))
        #expect(!keys.contains("DROID_CODE_GRAPH_INSTRUCTIONS"))
    }
    @Test
    func addsBrowserEnvironmentForWorktreePath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.makeInstalledRuntime()

        let values = Dictionary(uniqueKeysWithValues: CodingAgentShimEnvironment.variables(
            projectID: fixture.projectID,
            worktreeID: fixture.worktreeID,
            worktreePath: fixture.root.appendingPathComponent("project").path,
            browserCommandOverride: fixture.bin.appendingPathComponent("droid-browser-mcp").path,
            environment: ["PATH": fixture.bin.path],
            homeDirectory: fixture.home.path,
            store: fixture.store,
            fileManager: fixture.fileManager
        ).map { ($0.key, $0.value) })

        #expect(values["DROID_BROWSER_SESSION_ID"] != nil)
        #expect(values["DROID_BROWSER_ENDPOINT"]?.hasPrefix("http://127.0.0.1:") == true)
        #expect(values["DROID_BROWSER_MCP_COMMAND"]?.hasSuffix("droid-browser-mcp") == true)
    }

}

@MainActor
private final class Fixture {
    let fileManager = FileManager.default
    let root: URL
    let bin: URL
    let home: URL
    let store: DroidCodeGraphStore
    let projectID = UUID()
    let worktreeID = UUID()

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        bin = root.appendingPathComponent("bin", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        let graphRoot = root.appendingPathComponent("droidcodegraph", isDirectory: true)
        store = DroidCodeGraphStore(fileURL: graphRoot.appendingPathComponent("state.json"))
        try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    func makeInstalledGraph() throws {
        try makeInstalledRuntime()
        let graph = store.droidGraphURL(projectID: projectID, worktreeID: worktreeID)
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
}

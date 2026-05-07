import Foundation
import Testing

@testable import Droid

@MainActor
struct CodingAgentShimScriptStateTests {
    @Test
    func directShimFallsBackWhenCodeGraphStateIsDisabled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.writeGraph(state: "{\"isEnabled\":false,\"phase\":\"installed\"}")

        let result = try fixture.runCodexShim(args: ["hello"])

        #expect(result == ["hello"])
        #expect(!fixture.fileManager.fileExists(atPath: fixture.graphProject.appendingPathComponent("AGENTS.md").path))
    }

    @Test
    func directShimFallsBackWhenCodeGraphStateIsMissing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.writeGraph(state: nil)

        let result = try fixture.runCodexShim(args: ["hello"])

        #expect(result == ["hello"])
    }
}

@MainActor
private final class Fixture {
    let fileManager = FileManager.default
    let root: URL
    let home: URL
    let real: URL
    let output: URL
    let graphRoot: URL
    let project: URL
    let graphProject: URL
    let graphOutput: URL

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        real = root.appendingPathComponent("real-codex")
        output = root.appendingPathComponent("output.txt")
        graphRoot = root.appendingPathComponent("extensions/droidcodegraph", isDirectory: true)
        project = root.appendingPathComponent("project", isDirectory: true)
        graphProject = graphRoot.appendingPathComponent("projects/project/worktree", isDirectory: true)
        graphOutput = graphProject.appendingPathComponent("graphify-out", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$CAPTURE\"\n".utf8).write(to: real)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: real.path)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    func writeGraph(state: String?) throws {
        try fileManager.createDirectory(at: graphOutput, withIntermediateDirectories: true)
        try Data("{\"projectPath\":\"\(project.path)\"}".utf8).write(to: graphOutput.appendingPathComponent("droid-graph.json"))
        if let state {
            try Data(state.utf8).write(to: graphRoot.appendingPathComponent("state.json"))
        }
    }

    func runCodexShim(args: [String]) throws -> [String] {
        let shim = try #require(CodingAgentShimInstaller.install(
            homeDirectory: home.path,
            fileManager: fileManager
        )).appendingPathComponent("codex")
        let process = Process()
        process.executableURL = shim
        process.arguments = args
        process.currentDirectoryURL = project
        process.environment = ProcessInfo.processInfo.environment.merging([
            "DROID_REAL_CODEX": real.path,
            "DROID_CODE_GRAPH_ROOT_DIR": "extensions/droidcodegraph",
            "CAPTURE": output.path,
        ]) { _, new in new }
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return try String(contentsOf: output, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
            .map { $0.replacingOccurrences(of: root.path + "/", with: "") }
    }
}

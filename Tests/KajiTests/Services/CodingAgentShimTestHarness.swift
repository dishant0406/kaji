import Foundation
import Testing

@testable import Kaji

@MainActor
enum CodingAgentShimTestHarness {
    static func runShim(
        named name: String,
        realEnv: String,
        graphEnv: [String: String],
        args: [String],
        root providedRoot: URL? = nil,
        workingDirectory: URL? = nil,
        installBrowserMCP: Bool = false
    ) throws -> [String] {
        let fileManager = FileManager.default
        let root = providedRoot ?? fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let real = root.appendingPathComponent("real-\(name)")
        let output = root.appendingPathComponent("output.txt")
        let removesRoot = providedRoot == nil
        defer {
            if removesRoot { try? fileManager.removeItem(at: root) }
        }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try createEnvironmentFiles(graphEnv: graphEnv, root: root, fileManager: fileManager)
        try realExecutable(real)
        let shim = try #require(CodingAgentShimInstaller.install(
            homeDirectory: home.path,
            fileManager: fileManager,
            installBrowserMCP: installBrowserMCP
        )).appendingPathComponent(name)
        try run(shim, env: environment(
            realEnv: realEnv,
            real: real,
            output: output,
            graphEnv: graphEnv,
            root: root
        ), args: args, workingDirectory: workingDirectory)
        return try capturedOutput(output: output, root: root)
    }

    private static func createEnvironmentFiles(graphEnv: [String: String], root: URL, fileManager: FileManager) throws {
        for value in graphEnv.values {
            let url = root.appendingPathComponent(value)
            if value.hasSuffix(".md") || value.hasSuffix(".json") {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("ok".utf8).write(to: url)
            } else {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    private static func realExecutable(_ real: URL) throws {
        try Data("#!/bin/sh\nprintf 'OPENCODE_CONFIG=%s\\n' \"${OPENCODE_CONFIG:-}\" > \"$CAPTURE\"\nprintf '%s\\n' \"$@\" >> \"$CAPTURE\"\n".utf8).write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: real.path)
    }

    private static func environment(
        realEnv: String,
        real: URL,
        output: URL,
        graphEnv: [String: String],
        root: URL
    ) -> [String: String] {
        graphEnv.reduce(into: baseEnvironment(realEnv: realEnv, real: real, output: output, root: root)) { result, pair in
            result[pair.key] = root.appendingPathComponent(pair.value).path
        }
    }

    private static func baseEnvironment(realEnv: String, real: URL, output: URL, root: URL) -> [String: String] {
        [
            realEnv: real.path,
            "CAPTURE": output.path,
            "HOME": root.appendingPathComponent("home").path,
            "KAJI_CODE_GRAPH_INSTRUCTIONS": "",
            "KAJI_CODE_GRAPH_PROJECT_DIR": "",
            "KAJI_CODE_GRAPH_ROOT_DIR": root.appendingPathComponent("inactive-kajicodegraph").path,
            "KAJI_CODE_GRAPH_REPORT": "",
            "KAJI_CODE_GRAPH_JSON": "",
            "KAJI_CODE_GRAPH_OPENCODE_CONFIG": "",
            "KAJI_BROWSER_BROKER_URL": "",
            "KAJI_BROWSER_CDP_PORT": "",
            "KAJI_BROWSER_CDP_URL": "",
            "KAJI_BROWSER_MCP_COMMAND": "",
            "KAJI_BROWSER_MCP_TOKEN": "",
            "KAJI_BROWSER_SESSION_ID": "",
            "KAJI_CODEX_BROWSER_MCP_ARGS": "",
            "KAJI_CLAUDE_BROWSER_MCP_CONFIG": "",
            "KAJI_OPENCODE_BROWSER_MCP_CONFIG": "",
            "KAJI_PI_BROWSER_MCP_CONFIG": "",
        ]
    }

    private static func run(_ executable: URL, env: [String: String], args: [String], workingDirectory: URL?) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private static func capturedOutput(output: URL, root: URL) throws -> [String] {
        try String(contentsOf: output, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
            .map { $0.replacingOccurrences(of: root.path + "/", with: "") }
            .filter { !$0.hasPrefix("OPENCODE_CONFIG=") || $0 == "OPENCODE_CONFIG=opencode.json" || $0 == "OPENCODE_CONFIG=configs/opencode-browser-mcp.json" }
    }
}

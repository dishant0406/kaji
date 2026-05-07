import Foundation
import Testing

@testable import Droid

@MainActor
struct CodingAgentShimTests {
    @Test
    func installsExecutableShims() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }

        let directory = try #require(CodingAgentShimInstaller.install(
            homeDirectory: home.path,
            fileManager: fileManager
        ))

        for name in ["codex", "claude", "claude-code", "opencode", "pi"] {
            let path = directory.appendingPathComponent(name).path
            #expect(fileManager.isExecutableFile(atPath: path))
            let text = try String(contentsOfFile: path, encoding: .utf8)
            #expect(text.contains("exec \"$real\""))
            #expect(text.contains("\"$@\""))
        }
    }

    @Test
    func terminalEnvironmentPrependsShimsAndResolvesRealCommands() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try executable("codex", in: bin, fileManager: fileManager)

        let values = Dictionary(uniqueKeysWithValues: CodingAgentShimEnvironment.variables(
            projectID: UUID(),
            worktreeID: UUID(),
            environment: ["PATH": bin.path],
            homeDirectory: home.path,
            fileManager: fileManager
        ).map { ($0.key, $0.value) })

        let shimDirectory = CodingAgentShimInstaller.directory(homeDirectory: home.path).path
        #expect(values["PATH"]?.hasPrefix(shimDirectory + ":") == true)
        #expect(values["DROID_REAL_CODEX"] == bin.appendingPathComponent("codex").path)
        #expect(values["DROID_AGENT_SHIM_DIR"] == shimDirectory)
        #expect(values["ZDOTDIR"] == DroidShellBootstrapInstaller.directory(homeDirectory: home.path).path)
        #expect(values["DROID_USER_ZDOTDIR"] == home.path)
        #expect(fileManager.fileExists(atPath: DroidShellBootstrapInstaller.directory(homeDirectory: home.path).appendingPathComponent(".zshrc").path))
    }

    @Test
    func shellBootstrapSourcesUserZshThenRestoresShimPath() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let userZdotdir = root.appendingPathComponent("user-zsh", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: userZdotdir, withIntermediateDirectories: true)
        try Data("export PATH=/real/bin:$PATH\n".utf8).write(to: userZdotdir.appendingPathComponent(".zshrc"))

        let values = Dictionary(uniqueKeysWithValues: DroidShellBootstrapInstaller.install(
            homeDirectory: home.path,
            userZdotdir: userZdotdir.path,
            fileManager: fileManager
        ).map { ($0.key, $0.value) })
        let zshrc = try String(
            contentsOf: URL(fileURLWithPath: values["ZDOTDIR"] ?? "").appendingPathComponent(".zshrc"),
            encoding: .utf8
        )

        #expect(values["DROID_USER_ZDOTDIR"] == userZdotdir.path)
        #expect(zshrc.contains(". \"$_droid_user_zdotdir/.zshrc\""))
        #expect(zshrc.contains("PATH=\"$DROID_AGENT_SHIM_DIR:$PATH\""))
    }

    @Test
    func codexShimPreservesUserArgumentsAndAdditionalDirectories() throws {
        let result = try runShim(named: "codex", realEnv: "DROID_REAL_CODEX", graphEnv: [
            "DROID_CODE_GRAPH_PROJECT_DIR": "droid-graph",
        ], args: ["--add-dir", "user-extra", "hello"])

        #expect(result == ["--add-dir", "droid-graph", "--add-dir", "user-extra", "hello"])
    }

    @Test
    func piShimUsesNativeAppendSystemPrompt() throws {
        let result = try runShim(named: "pi", realEnv: "DROID_REAL_PI", graphEnv: [
            "DROID_CODE_GRAPH_INSTRUCTIONS": "instructions/AGENTS.md",
        ], args: ["hello"])

        #expect(result == ["--append-system-prompt", "instructions/AGENTS.md", "hello"])
    }

    @Test
    func claudeShimUsesNativeAdditionalDirectory() throws {
        let result = try runShim(named: "claude", realEnv: "DROID_REAL_CLAUDE", graphEnv: [
            "DROID_CODE_GRAPH_PROJECT_DIR": "droid-graph",
        ], args: ["hello"])

        #expect(result == ["--add-dir", "droid-graph", "hello"])
    }

    @Test
    func openCodeShimUsesNativeConfigEnvironment() throws {
        let result = try runShim(named: "opencode", realEnv: "DROID_REAL_OPENCODE", graphEnv: [
            "DROID_CODE_GRAPH_OPENCODE_CONFIG": "opencode.json",
        ], args: ["run", "hello"])

        #expect(result == ["OPENCODE_CONFIG=opencode.json", "run", "hello"])
    }

    private func runShim(
        named name: String,
        realEnv: String,
        graphEnv: [String: String],
        args: [String]
    ) throws -> [String] {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let real = root.appendingPathComponent("real-\(name)")
        let output = root.appendingPathComponent("output.txt")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        for value in graphEnv.values {
            let url = root.appendingPathComponent(value)
            if value.hasSuffix(".md") || value.hasSuffix(".json") {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("ok".utf8).write(to: url)
            } else {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
        try Data("#!/bin/sh\nprintf 'OPENCODE_CONFIG=%s\\n' \"${OPENCODE_CONFIG:-}\" > \"$CAPTURE\"\nprintf '%s\\n' \"$@\" >> \"$CAPTURE\"\n".utf8).write(to: real)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: real.path)

        let shim = try #require(CodingAgentShimInstaller.install(
            homeDirectory: home.path,
            fileManager: fileManager
        )).appendingPathComponent(name)
        let env = graphEnv.reduce(into: [
            realEnv: real.path,
            "CAPTURE": output.path,
        ]) { result, pair in
            result[pair.key] = root.appendingPathComponent(pair.value).path
        }
        try run(shim, env: env, args: args)

        return try String(contentsOf: output, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
            .filter { $0 != "OPENCODE_CONFIG=" }
            .map { $0.replacingOccurrences(of: root.path + "/", with: "") }
    }

    private func executable(_ name: String, in directory: URL, fileManager: FileManager) throws {
        let path = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }

    private func run(_ executable: URL, env: [String: String], args: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

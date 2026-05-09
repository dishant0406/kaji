import Foundation
import Testing

@testable import Droid

@MainActor
struct CodingAgentShimNvmResolutionTests {
    @Test
    func shimPrefersLatestNvmExecutableOverStaleRealEnvironment() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let output = root.appendingPathComponent("output.txt")
        let old = home
            .appendingPathComponent(".nvm/versions/node/v22.15.0/bin", isDirectory: true)
            .appendingPathComponent("codex")
        let latest = home
            .appendingPathComponent(".nvm/versions/node/v22.20.0/bin", isDirectory: true)
            .appendingPathComponent("codex")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: latest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf 'old\\n' > \"$CAPTURE\"\n".utf8).write(to: old)
        try Data("#!/bin/sh\nprintf 'new\\n' > \"$CAPTURE\"\n".utf8).write(to: latest)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: old.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: latest.path)

        let shim = try #require(CodingAgentShimInstaller.install(
            homeDirectory: home.path,
            fileManager: fileManager
        )).appendingPathComponent("codex")
        try run(shim, env: [
            "HOME": home.path,
            "DROID_REAL_CODEX": old.path,
            "DROID_CODE_GRAPH_INSTRUCTIONS": "",
            "DROID_CODE_GRAPH_PROJECT_DIR": "",
            "DROID_CODE_GRAPH_ROOT_DIR": root.appendingPathComponent("inactive").path,
            "DROID_CODE_GRAPH_REPORT": "",
            "DROID_CODE_GRAPH_JSON": "",
            "DROID_CODE_GRAPH_OPENCODE_CONFIG": "",
            "CAPTURE": output.path,
        ], args: [])

        #expect(try String(contentsOf: output, encoding: .utf8) == "new\n")
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

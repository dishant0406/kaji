import Foundation
import Testing

@testable import Droid

struct DroidShellBootstrapInstallerTests {
    @Test
    func agentFunctionsOverrideUserPathChanges() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let userZdotdir = root.appendingPathComponent("user-zsh", isDirectory: true)
        let realBin = root.appendingPathComponent("real-bin", isDirectory: true)
        let shimBin = root.appendingPathComponent("shim-bin", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: userZdotdir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: realBin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: shimBin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("export PATH=\(realBin.path):$PATH\n".utf8).write(to: userZdotdir.appendingPathComponent(".zshrc"))
        try executable("codex", output: "real", in: realBin, fileManager: fileManager)
        try executable("codex", output: "shim", in: shimBin, fileManager: fileManager)

        let values = Dictionary(uniqueKeysWithValues: DroidShellBootstrapInstaller.install(
            homeDirectory: home.path,
            userZdotdir: userZdotdir.path,
            fileManager: fileManager
        ).map { ($0.key, $0.value) })
        let output = try runZsh(
            env: [
                "HOME": home.path,
                "PATH": "/usr/bin:/bin",
                "DROID_AGENT_SHIM_DIR": shimBin.path,
                "DROID_USER_ZDOTDIR": userZdotdir.path,
                "ZDOTDIR": values["ZDOTDIR"] ?? "",
            ],
            command: "codex hello"
        )

        #expect(output == "shim:hello")
    }

    private func executable(
        _ name: String,
        output: String,
        in directory: URL,
        fileManager: FileManager
    ) throws {
        let path = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nprintf '\(output):%s\\n' \"$*\"\n".utf8).write(to: path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }

    private func runZsh(env: [String: String], command: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", command]
        process.environment = env
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

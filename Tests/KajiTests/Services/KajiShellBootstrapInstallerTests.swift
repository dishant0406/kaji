import Foundation
import Testing

@testable import Kaji

struct KajiShellBootstrapInstallerTests {
    @Test
    func sourcesUserZshThenRestoresShimPath() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let userZdotdir = root.appendingPathComponent("user-zsh", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: userZdotdir, withIntermediateDirectories: true)
        try Data("export PATH=/real/bin:$PATH\n".utf8).write(to: userZdotdir.appendingPathComponent(".zshrc"))

        let values = Dictionary(uniqueKeysWithValues: KajiShellBootstrapInstaller.install(
            homeDirectory: home.path,
            userZdotdir: userZdotdir.path,
            fileManager: fileManager
        ).map { ($0.key, $0.value) })
        let zshrc = try String(
            contentsOf: URL(fileURLWithPath: values["ZDOTDIR"] ?? "").appendingPathComponent(".zshrc"),
            encoding: .utf8
        )

        #expect(values["KAJI_USER_ZDOTDIR"] == userZdotdir.path)
        #expect(zshrc.contains(". \"$_kaji_user_zdotdir/.zshrc\""))
        #expect(zshrc.contains("$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"))
        #expect(zshrc.contains("PATH=\"$KAJI_AGENT_SHIM_DIR:$PATH\""))
    }

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

        let values = Dictionary(uniqueKeysWithValues: KajiShellBootstrapInstaller.install(
            homeDirectory: home.path,
            userZdotdir: userZdotdir.path,
            fileManager: fileManager
        ).map { ($0.key, $0.value) })
        let output = try runZsh(
            env: [
                "HOME": home.path,
                "PATH": "/usr/bin:/bin",
                "KAJI_AGENT_SHIM_DIR": shimBin.path,
                "KAJI_USER_ZDOTDIR": userZdotdir.path,
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

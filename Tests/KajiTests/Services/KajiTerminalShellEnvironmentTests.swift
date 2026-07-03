import Foundation
import Testing

@testable import Kaji

struct KajiTerminalShellEnvironmentTests {
    @Test
    @MainActor
    func installsOnlyShellBootstrapVariables() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let userZdotdir = root.appendingPathComponent("user-zsh", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: userZdotdir, withIntermediateDirectories: true)

        let values = Dictionary(uniqueKeysWithValues: KajiTerminalShellEnvironment.variables(
            environment: ["ZDOTDIR": userZdotdir.path],
            homeDirectory: home.path,
            fileManager: fileManager,
            browserEnabled: true
        ).map { ($0.key, $0.value) })

        #expect(values["ZDOTDIR"]?.hasSuffix(".kaji/shell/zsh") == true)
        #expect(values["KAJI_USER_ZDOTDIR"] == userZdotdir.path)
        #expect(values["PATH"] == nil)
        #expect(values["KAJI_AGENT_SHIM_DIR"] == nil)
        #expect(values["KAJI_REAL_CODEX"] == nil)
    }

    @Test
    @MainActor
    func removesBrowserSessionWhenBrowserIsDisabled() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let session = KajiBrowserSessionEnvironmentStore.fileURL(homeDirectory: home.path)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: session)

        _ = KajiTerminalShellEnvironment.variables(
            homeDirectory: home.path,
            fileManager: fileManager,
            browserEnabled: false
        )

        #expect(!fileManager.fileExists(atPath: session.path))
    }
}

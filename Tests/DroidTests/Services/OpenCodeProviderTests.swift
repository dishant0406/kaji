import Foundation
import Testing

@testable import Droid

struct OpenCodeProviderTests {
    @Test
    func pluginPathsIncludeCurrentAndLegacyDirectories() {
        let paths = OpenCodeProvider.pluginPaths(homeDirectory: "/tmp/home")

        #expect(paths == [
            "/tmp/home/.config/opencode/plugins/droid-notify.js",
            "/tmp/home/.opencode/plugins/droid-notify.js",
        ])
    }

    @Test
    func installCopiesLatestPluginToCurrentAndLegacyDirectories() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scriptsDir = tempRoot.appendingPathComponent("scripts")
        let homeDir = tempRoot.appendingPathComponent("home")
        try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)

        let hookScript = scriptsDir.appendingPathComponent("droid-claude-hook.sh")
        let pluginScript = scriptsDir.appendingPathComponent("opencode-droid-plugin.js")

        try "#!/bin/bash\n".data(using: .utf8)?.write(to: hookScript)
        try """
        export const DroidNotificationPlugin = async () => ({
          event: async ({ event }) => {
            const projectID = process.env.DROID_PROJECT_ID
            const worktreeID = process.env.DROID_WORKTREE_ID
            const raw = event.properties?.status
            if (typeof raw === "string") return raw
            if (raw && typeof raw.type === "string") return raw.type
            if (raw === "busy" || raw === "retry") return raw
            if (event.type === "tui.command.execute") return
            if (event.type === "tool.execute.before") return
            if (event.type === "session.idle") await stop()
            if (projectID && worktreeID) return
          },
        })
        """.data(using: .utf8)?.write(to: pluginScript)

        let provider = OpenCodeProvider()
        try provider.install(
            hookScriptPath: hookScript.path,
            homeDirectory: homeDir.path,
            fileManager: fileManager
        )

        for path in OpenCodeProvider.pluginPaths(homeDirectory: homeDir.path) {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            #expect(text.contains("tui.command.execute"))
            #expect(text.contains("tool.execute.before"))
            #expect(text.contains("await stop()"))
            #expect(text.contains("typeof raw === \"string\""))
            #expect(text.contains("raw.type"))
            #expect(text.contains("busy"))
            #expect(text.contains("retry"))
            #expect(text.contains("DROID_PROJECT_ID"))
            #expect(text.contains("DROID_WORKTREE_ID"))
        }
    }

    @Test
    func installRemovesObsoleteMuxyPlugin() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scriptsDir = tempRoot.appendingPathComponent("scripts")
        let homeDir = tempRoot.appendingPathComponent("home")
        try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homeDir, withIntermediateDirectories: true)

        let hookScript = scriptsDir.appendingPathComponent("droid-claude-hook.sh")
        let pluginScript = scriptsDir.appendingPathComponent("opencode-droid-plugin.js")
        let obsoletePlugin = homeDir
            .appendingPathComponent(".opencode")
            .appendingPathComponent("plugins")
            .appendingPathComponent("muxy-notify.js")

        try "#!/bin/bash\n".data(using: .utf8)?.write(to: hookScript)
        try "export const DroidNotificationPlugin = async () => ({})\n".data(using: .utf8)?.write(to: pluginScript)
        try fileManager.createDirectory(at: obsoletePlugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "export const MuxyNotificationPlugin = async () => ({})\n".data(using: .utf8)?.write(to: obsoletePlugin)

        let provider = OpenCodeProvider()
        try provider.install(
            hookScriptPath: hookScript.path,
            homeDirectory: homeDir.path,
            fileManager: fileManager
        )

        #expect(!fileManager.fileExists(atPath: obsoletePlugin.path))
    }
}

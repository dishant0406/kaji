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
            if (event.type === "tui.command.execute") return
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
        }
    }
}

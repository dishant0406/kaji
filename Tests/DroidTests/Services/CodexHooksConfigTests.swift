import Foundation
import Testing

@testable import Droid

struct CodexHooksConfigTests {
    @Test
    func installEnablesCodexHooksInsideExistingFeaturesSection() {
        let input = """
        model = "gpt-5.4"

        [features]
        shell_snapshot = true
        """

        let output = CodexHooksConfig.install(
            config: input,
            hooksContent: "",
            hookClientPath: "/tmp/DroidHookClient"
        )

        #expect(output.config.contains("[features]"))
        #expect(output.config.contains("codex_hooks = true"))
        #expect(output.config.contains("shell_snapshot = true"))
    }

    @Test
    func installAddsFeaturesSectionWhenMissing() {
        let output = CodexHooksConfig.install(
            config: "model = \"gpt-5.4\"\n",
            hooksContent: "",
            hookClientPath: "/tmp/DroidHookClient"
        )

        #expect(output.config.contains("[features]"))
        #expect(output.config.contains("codex_hooks = true"))
    }

    @Test
    func installMergesDroidHooksWithoutDroppingExistingEntries() {
        let hooks = """
        {
          "hooks": {
            "UserPromptSubmit": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/tmp/custom-start.sh"
                  }
                ]
              }
            ]
          }
        }
        """

        let output = CodexHooksConfig.install(
            config: "",
            hooksContent: hooks,
            hookClientPath: "/tmp/DroidHookClient"
        )

        let commands = hookCommands(in: output.hooks)
        #expect(commands.contains("/tmp/custom-start.sh"))
        #expect(commands.contains(where: { $0.contains("DROID_HOOK_CLIENT_PATH") && $0.contains("codex-activity codex start") }))
        #expect(commands.contains(where: { $0.contains("DROID_HOOK_CLIENT_PATH") && $0.contains("codex-activity codex stop") }))
        #expect(commands.contains(where: { $0.contains("DROID_HOOK_CLIENT_PATH") && $0.contains("codex-activity codex attention") }))
        #expect(commands.allSatisfy { $0.contains("droid-activity-hook") || $0 == "/tmp/custom-start.sh" })
    }

    @Test
    func installUsesRuntimeHookClientEnvironmentBeforeFallbackPath() {
        let output = CodexHooksConfig.install(
            config: "",
            hooksContent: "",
            hookClientPath: "/tmp/Droid Hook Client"
        )

        let commands = hookCommands(in: output.hooks)
        #expect(commands.contains { command in
            command.contains("$DROID_HOOK_CLIENT_PATH") &&
                command.contains("'/tmp/Droid Hook Client'") &&
                command.contains("codex-activity codex start")
        })
        #expect(hookHandlers(in: output.hooks).contains { ($0["timeout"] as? Int) == 5 })
    }

    @Test
    func uninstallRemovesOnlyDroidEntries() {
        let hooks = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/tmp/custom-stop.sh"
                  }
                ]
              },
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/tmp/DroidHookClient codex-activity codex stop # droid-activity-hook"
                  }
                ]
              }
            ],
            "PermissionRequest": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/tmp/DroidHookClient codex-activity codex attention # droid-activity-hook"
                  }
                ]
              }
            ]
          }
        }
        """

        let output = CodexHooksConfig.uninstall(from: hooks)

        let commands = hookCommands(in: output)
        #expect(commands.contains("/tmp/custom-stop.sh"))
        #expect(!commands.contains(where: { $0.contains("droid-activity-hook") }))
    }

    private func hookCommands(in json: String) -> [String] {
        hookHandlers(in: json).compactMap { $0["command"] as? String }
    }

    private func hookHandlers(in json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any]
        else {
            return []
        }

        return hooks.values
            .compactMap { $0 as? [[String: Any]] }
            .flatMap { entries in
                entries.flatMap { entry in
                    (entry["hooks"] as? [[String: Any]]) ?? []
                }
            }
    }
}

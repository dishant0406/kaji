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
            activityScriptPath: "/tmp/droid-ai-activity.sh"
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
            activityScriptPath: "/tmp/droid-ai-activity.sh"
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
            activityScriptPath: "/tmp/droid-ai-activity.sh"
        )

        let commands = hookCommands(in: output.hooks)
        #expect(commands.contains("/tmp/custom-start.sh"))
        #expect(commands.contains("'/tmp/droid-ai-activity.sh' codex start # droid-activity-hook"))
        #expect(commands.contains("'/tmp/droid-ai-activity.sh' codex stop # droid-activity-hook"))
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
                    "command": "'/tmp/droid-ai-activity.sh' codex stop # droid-activity-hook"
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
                    ((entry["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
                }
            }
    }
}

import Testing

@testable import Droid

struct CodexNotificationConfigTests {
    @Test
    func installAppendsManagedBlockWhenMissing() {
        let output = CodexNotificationConfig.install(in: "model = \"gpt-5\"\n", scriptPath: "/tmp/droid-codex-notify.sh")

        #expect(output.contains("model = \"gpt-5\""))
        #expect(output.contains(CodexNotificationConfig.startMarker))
        #expect(output.contains(#"notify = ["/tmp/droid-codex-notify.sh"]"#))
    }

    @Test
    func installReplacesExistingNotifyBlock() {
        let input = """
        sandbox_mode = "workspace-write"
        notify = [
          "terminal-notifier",
          "Codex"
        ]
        """

        let output = CodexNotificationConfig.install(in: input, scriptPath: "/tmp/droid-codex-notify.sh")

        #expect(!output.contains("terminal-notifier"))
        #expect(output.contains(#"notify = ["/tmp/droid-codex-notify.sh"]"#))
    }

    @Test
    func uninstallRemovesManagedBlockOnly() {
        let input = """
        model = "gpt-5"

        # droid-notify-start
        notify = ["/tmp/droid-codex-notify.sh"]
        # droid-notify-end
        """

        let output = CodexNotificationConfig.uninstall(from: input)

        #expect(output == "model = \"gpt-5\"\n")
    }
}

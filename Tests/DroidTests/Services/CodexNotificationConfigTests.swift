import Testing

@testable import Droid

struct CodexNotificationConfigTests {
    @Test
    func installAppendsManagedBlockWhenMissing() {
        let output = CodexNotificationConfig.install(in: "model = \"gpt-5\"\n", scriptPath: "/tmp/droid-codex-notify.sh")

        #expect(output.contains("model = \"gpt-5\""))
        #expect(output.contains(CodexNotificationConfig.startMarker))
        #expect(output.contains(#"notify = ["/bin/bash", "/tmp/droid-codex-notify.sh"]"#))
    }

    @Test
    func installWrapsExistingNotifyBlock() {
        let input = """
        sandbox_mode = "workspace-write"
        notify = [
          "terminal-notifier",
          "Codex"
        ]
        """

        let output = CodexNotificationConfig.install(in: input, scriptPath: "/tmp/droid-codex-notify.sh")

        #expect(output.contains(#"# droid-notify-original = ["terminal-notifier", "Codex"]"#))
        #expect(output.contains(#"notify = ["/bin/bash", "/tmp/droid-codex-notify.sh", "--passthrough-count", "2", "terminal-notifier", "Codex"]"#))
    }

    @Test
    func installDropsLegacySkyComputerUsePassthrough() {
        let input = """
        notify = ["/Users/test/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient", "turn-ended"]
        """

        let output = CodexNotificationConfig.install(in: input, scriptPath: "/tmp/droid-codex-notify.sh")

        #expect(!output.contains("SkyComputerUseClient"))
        #expect(output.contains(#"notify = ["/bin/bash", "/tmp/droid-codex-notify.sh"]"#))
        #expect(!output.contains("# droid-notify-original"))
    }

    @Test
    func installMigratesManagedBlockAwayFromLegacySkyComputerUsePassthrough() {
        let input = """
        # droid-notify-start
        # droid-notify-original = ["/Users/test/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient", "turn-ended"]
        notify = ["/bin/bash", "/tmp/droid-codex-notify.sh", "--passthrough-count", "2", "/Users/test/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient", "turn-ended"]
        # droid-notify-end
        """

        let output = CodexNotificationConfig.install(in: input, scriptPath: "/tmp/droid-codex-notify.sh")

        #expect(!output.contains("SkyComputerUseClient"))
        #expect(output.contains(#"notify = ["/bin/bash", "/tmp/droid-codex-notify.sh"]"#))
        #expect(!output.contains("# droid-notify-original"))
    }

    @Test
    func installPlacesManagedBlockBeforeFirstTable() {
        let input = """
        approval_policy = "never"

        [tui.model_availability_nux]
        "gpt-5.5" = 1
        """

        let output = CodexNotificationConfig.install(in: input, scriptPath: "/tmp/droid-codex-notify.sh")

        let notifyIndex = output.range(of: #"notify = ["/bin/bash", "/tmp/droid-codex-notify.sh"]"#)?.lowerBound
        let tableIndex = output.range(of: "[tui.model_availability_nux]")?.lowerBound

        #expect(notifyIndex != nil)
        #expect(tableIndex != nil)
        #expect(notifyIndex! < tableIndex!)
        #expect(output.contains(
            """
            # droid-notify-end

            [tui.model_availability_nux]
            """
        ))
    }

    @Test
    func installConsumesExistingNotifyWhenManagedMarkersAreEmpty() {
        let input = """
        notify = ["terminal-notifier", "turn-ended"]

        # droid-notify-start
        # droid-notify-end
        """

        let output = CodexNotificationConfig.install(in: input, scriptPath: "/tmp/droid-codex-notify.sh")

        #expect(!output.contains(#"notify = ["terminal-notifier", "turn-ended"]"#))
        #expect(output.contains(#"# droid-notify-original = ["terminal-notifier", "turn-ended"]"#))
        #expect(output.contains(#"notify = ["/bin/bash", "/tmp/droid-codex-notify.sh", "--passthrough-count", "2", "terminal-notifier", "turn-ended"]"#))
    }

    @Test
    func uninstallRemovesManagedBlockOnly() {
        let input = """
        model = "gpt-5"

        # droid-notify-start
        notify = ["/bin/bash", "/tmp/droid-codex-notify.sh"]
        # droid-notify-end
        """

        let output = CodexNotificationConfig.uninstall(from: input)

        #expect(output == "model = \"gpt-5\"\n")
    }

    @Test
    func uninstallRestoresOriginalNotifyBlock() {
        let input = """
        # droid-notify-start
        # droid-notify-original = ["terminal-notifier", "turn-ended"]
        notify = ["/bin/bash", "/tmp/droid-codex-notify.sh", "--passthrough-count", "2", "terminal-notifier", "turn-ended"]
        # droid-notify-end
        """

        let output = CodexNotificationConfig.uninstall(from: input)

        #expect(output == #"notify = ["terminal-notifier", "turn-ended"]"# + "\n")
    }
}

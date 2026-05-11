import Testing

@testable import Kaji

struct CodexNotificationConfigTests {
    @Test
    func installNoLongerAddsCodexNotifyHook() {
        let output = CodexNotificationConfig.install(in: "model = \"gpt-5\"\n", scriptPath: "/tmp/ignored")

        #expect(output == "model = \"gpt-5\"\n")
        #expect(!output.contains("notify ="))
    }

    @Test
    func uninstallRemovesManagedBlockOnly() {
        let input = """
        model = "gpt-5"

        # kaji-notify-start
        notify = ["/bin/bash", "/tmp/legacy-notify.sh"]
        # kaji-notify-end
        """

        let output = CodexNotificationConfig.uninstall(from: input)

        #expect(output == "model = \"gpt-5\"\n")
    }

    @Test
    func uninstallRestoresOriginalNotifyBlock() {
        let input = """
        # kaji-notify-start
        # kaji-notify-original = ["terminal-notifier", "turn-ended"]
        notify = ["/bin/bash", "/tmp/legacy-notify.sh", "--passthrough-count", "2", "terminal-notifier", "turn-ended"]
        # kaji-notify-end
        """

        let output = CodexNotificationConfig.uninstall(from: input)

        #expect(output == #"notify = ["terminal-notifier", "turn-ended"]"# + "\n")
    }
}

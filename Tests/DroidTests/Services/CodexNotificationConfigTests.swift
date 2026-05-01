import Testing

@testable import Droid

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

        # droid-notify-start
        notify = ["/bin/bash", "/tmp/legacy-notify.sh"]
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
        notify = ["/bin/bash", "/tmp/legacy-notify.sh", "--passthrough-count", "2", "terminal-notifier", "turn-ended"]
        # droid-notify-end
        """

        let output = CodexNotificationConfig.uninstall(from: input)

        #expect(output == #"notify = ["terminal-notifier", "turn-ended"]"# + "\n")
    }
}

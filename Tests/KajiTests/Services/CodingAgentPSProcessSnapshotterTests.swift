import Testing

@testable import Kaji

struct CodingAgentPSProcessSnapshotterTests {
    @Test
    func parsesCodexAppServerRow() {
        let output = """
        20864 19904 19904 S ?? 0.0 28192 /Applications/Codex.app/Contents/Resources/codex codex app-server --analytics-default-enabled
        """

        let processes = CodingAgentPSProcessSnapshotter.parse(output)

        #expect(processes.first?.pid == 20864)
        #expect(processes.first?.parentPID == 19904)
        #expect(processes.first?.processGroupID == 19904)
        #expect(processes.first?.state == "S")
        #expect(processes.first?.tty == "??")
        #expect(processes.first?.commandName == "codex")
        #expect(processes.first?.commandLine == "codex app-server --analytics-default-enabled")
    }

    @Test
    func parsesOpenCodeNodeRow() {
        let output = """
        50777 49805 50777 S+ ttys001 0.0 29168 node node /Users/me/.nvm/versions/node/v22/bin/opencode --session abc
        """

        let process = CodingAgentPSProcessSnapshotter.parse(output).first

        #expect(process?.commandName == "node")
        #expect(process?.tty == "ttys001")
        #expect(process?.commandLine.contains("opencode --session abc") == true)
    }

    @Test
    func skipsMalformedRows() {
        #expect(CodingAgentPSProcessSnapshotter.parse("bad row").isEmpty)
    }
}

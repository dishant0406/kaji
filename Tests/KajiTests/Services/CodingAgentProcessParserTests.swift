import Testing

@testable import Kaji

struct CodingAgentProcessParserTests {
    @Test
    func parsesProcessRowsWithCommandArguments() {
        let output = """
        HEADER
          123  1  123  12.5  2048 /opt/homebrew/bin/opencode opencode --session abc
        """

        let processes = CodingAgentProcessParser.parse(output)

        #expect(processes == [CodingAgentProcessInfo(
            pid: 123,
            parentPID: 1,
            processGroupID: 123,
            cpuPercent: 12.5,
            memoryBytes: 2_097_152,
            commandName: "opencode",
            commandLine: "opencode --session abc"
        )])
    }

    @Test
    func skipsMalformedRows() {
        let output = """
        HEADER
        bad row
        1 2 3
        """

        #expect(CodingAgentProcessParser.parse(output).isEmpty)
    }
}

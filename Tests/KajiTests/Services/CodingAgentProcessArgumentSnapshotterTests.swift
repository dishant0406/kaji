import Testing

@testable import Kaji

struct CodingAgentProcessArgumentSnapshotterTests {
    @Test
    func parsesPIDArguments() {
        let output = """
          123 opencode --session abc
          456 node /tmp/app.js --flag
        """

        let arguments = CodingAgentProcessArgumentSnapshotter.parse(output)

        #expect(arguments[123] == "opencode --session abc")
        #expect(arguments[456] == "node /tmp/app.js --flag")
    }

    @Test
    func skipsMalformedRows() {
        let output = """
        bad row
        123
        """

        #expect(CodingAgentProcessArgumentSnapshotter.parse(output).isEmpty)
    }
}

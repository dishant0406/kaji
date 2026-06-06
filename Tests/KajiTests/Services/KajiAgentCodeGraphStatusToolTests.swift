import Foundation
import Testing

@testable import Kaji

struct KajiAgentCodeGraphStatusToolTests {
    @Test
    func missingGraphIsNonErrorStatus() throws {
        let result = KajiAgentCodeGraphStatusTool.result(.init(
            hasActiveProject: true,
            hasReport: false,
            hasGraph: false,
            isRunning: false,
            reportURL: URL(fileURLWithPath: "/tmp/GRAPH_REPORT.md"),
            graphURL: URL(fileURLWithPath: "/tmp/kaji-graph.json"),
            lastError: nil
        ))
        let details = try #require(result.details?.objectValue)

        #expect(result.isError == false)
        #expect(details["kind"]?.stringValue == "codeGraphStatus")
        #expect(details["ready"]?.boolValue == false)
        #expect(details["hasReport"]?.boolValue == false)
        #expect(details["hasGraph"]?.boolValue == false)
        #expect(details["reportPath"]?.stringValue == "/tmp/GRAPH_REPORT.md")
        #expect(details["graphPath"]?.stringValue == "/tmp/kaji-graph.json")
    }

    @Test
    func readyGraphIsNonErrorStatus() throws {
        let result = KajiAgentCodeGraphStatusTool.result(.init(
            hasActiveProject: true,
            hasReport: true,
            hasGraph: true,
            isRunning: false,
            reportURL: URL(fileURLWithPath: "/tmp/GRAPH_REPORT.md"),
            graphURL: URL(fileURLWithPath: "/tmp/kaji-graph.json"),
            lastError: nil
        ))
        let details = try #require(result.details?.objectValue)

        #expect(result.isError == false)
        #expect(details["ready"]?.boolValue == true)
        #expect(result.content.first?.text == "CodeGraph ready: yes")
    }
}

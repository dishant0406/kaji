import Foundation
import Testing

@testable import Kaji

struct KajiAgentCodeGraphMissingResultTests {
    @Test
    func includesStructuredMissingReportDetails() throws {
        let result = KajiAgentCodeGraphMissingResult.report(
            reportURL: URL(fileURLWithPath: "/tmp/GRAPH_REPORT.md"),
            graphURL: URL(fileURLWithPath: "/tmp/kaji-graph.json")
        )
        let details = try #require(result.details?.objectValue)

        #expect(result.isError == true)
        #expect(details["kind"]?.stringValue == "codeGraphMissing")
        #expect(details["missing"]?.stringValue == "report")
        #expect(details["missingGraph"]?.boolValue == true)
        #expect(details["reportPath"]?.stringValue == "/tmp/GRAPH_REPORT.md")
        #expect(details["graphPath"]?.stringValue == "/tmp/kaji-graph.json")
    }
}

import Foundation
import Testing

@testable import Muxy

@Suite("AmpUsageParser")
struct AmpUsageParserTests {
    @Test("parses balance and credits from display text")
    func parseRows() throws {
        let json = """
        {
          "ok": true,
          "result": {
            "displayText": "Amp Free: $48/$50 remaining, replenishes +$2/hour. Individual credits: $7.5 remaining"
          }
        }
        """

        let rows = try AmpUsageParser.parseMetricRows(from: Data(json.utf8))
        #expect(rows.count == 2)
        #expect(rows[0].label == "Free balance")
        #expect(rows[0].percent == 4)
        #expect(rows[1].label == "Credits")
    }
}

import Foundation
import Testing

@testable import Muxy

@Suite("ZaiUsageParser")
struct ZaiUsageParserTests {
    @Test("parses session weekly and web search rows")
    func parseRows() throws {
        let json = """
        {
          "data": {
            "limits": [
              {"limitType":"TOKENS_LIMIT","unit":3,"percentage":12,"nextResetTime":1745500000},
              {"limitType":"TOKENS_LIMIT","unit":6,"percentage":30,"nextResetTime":1746000000},
              {"limitType":"TIME_LIMIT","currentValue":14,"usage":100,"nextResetTime":1746600000}
            ]
          }
        }
        """

        let rows = try ZaiUsageParser.parseMetricRows(quotaData: Data(json.utf8))
        #expect(rows.count == 3)
        #expect(rows[0].label == "Session")
        #expect(rows[0].percent == 12)
        #expect(rows[1].label == "Weekly")
        #expect(rows[1].percent == 30)
        #expect(rows[2].label == "Web searches")
        #expect(Int((rows[2].percent ?? 0).rounded()) == 14)
    }

    @Test("parses plan name from subscription list")
    func parsePlanName() {
        let json = """
        {"data":[{"productName":"Z.ai Pro"}]}
        """

        let plan = ZaiUsageParser.parsePlanName(subscriptionData: Data(json.utf8))
        #expect(plan == "Z.ai Pro")
    }
}

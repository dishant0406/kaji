import Foundation
import Testing

@testable import Muxy

@Suite("FactoryUsageParser")
struct FactoryUsageParserTests {
    @Test("parses standard and premium rows with inferred plan name")
    func parseStandardAndPremium() throws {
        let json = """
        {
          "usage": {
            "startDate": 1735689600000,
            "endDate": 1738368000000,
            "standard": { "totalAllowance": 20000000, "orgTotalTokensUsed": 5000000 },
            "premium": { "totalAllowance": 1000000, "orgTotalTokensUsed": 250000 }
          }
        }
        """

        let parsed = try FactoryUsageParser.parse(from: Data(json.utf8))

        #expect(parsed.planName == "Pro")
        #expect(parsed.rows.count == 2)
        #expect(parsed.rows[0].label == "Standard")
        #expect(parsed.rows[0].percent == 25)
        #expect(parsed.rows[1].label == "Premium")
        #expect(parsed.rows[1].percent == 25)
    }

    @Test("skips premium row when allowance is zero")
    func skipsEmptyPremium() throws {
        let json = """
        {
          "usage": {
            "startDate": 1735689600000,
            "endDate": 1738368000000,
            "standard": { "totalAllowance": 5000000, "orgTotalTokensUsed": 1000000 },
            "premium": { "totalAllowance": 0, "orgTotalTokensUsed": 0 }
          }
        }
        """

        let parsed = try FactoryUsageParser.parse(from: Data(json.utf8))
        #expect(parsed.planName == "Basic")
        #expect(parsed.rows.count == 1)
        #expect(parsed.rows[0].label == "Standard")
    }
}

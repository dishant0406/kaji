import Foundation
import Testing

@testable import Muxy

@Suite("ClaudeUsageParser")
struct ClaudeUsageParserTests {
    @Test("parses known usage windows using utilization percentages")
    func parseKnownWindows() throws {
        let json = """
        {
          "five_hour": {
            "utilization": 20,
            "resets_at": 1735779600
          },
          "seven_day": {
            "utilization": 70,
            "resets_at": "2026-04-20T12:00:00.000Z"
          },
          "seven_day_sonnet": {
            "utilization": 50,
            "resets_at": 1735783200000
          },
          "seven_day_omelette": {
            "utilization": 100,
            "resets_at": 1735783200
          }
        }
        """

        let rows = try ClaudeUsageParser.parseMetricRows(from: Data(json.utf8))

        #expect(rows.count == 4)
        #expect(rows.map(\.label) == ["5h", "7d", "7d Sonnet", "7d Omelette"])
        #expect(rows.map(\.percent) == [20, 70, 50, 100])
        #expect(rows[0].detail == "20.0% used")
        #expect(rows[3].detail == "100% used")
        #expect(rows.allSatisfy { $0.resetDate != nil })
    }

    @Test("parses extra_usage credits into a row")
    func parseExtraUsageCredits() throws {
        let json = """
        {
          "five_hour": { "utilization": 5, "resets_at": 1735779600 },
          "extra_usage": { "used_credits": 12.5, "monthly_limit": 100 }
        }
        """

        let rows = try ClaudeUsageParser.parseMetricRows(from: Data(json.utf8))

        #expect(rows.count == 2)
        #expect(rows[1].label == "Credits")
        #expect(rows[1].percent == nil)
        #expect(rows[1].detail?.contains("12") == true)
        #expect(rows[1].detail?.contains("100") == true)
    }

    @Test("ignores windows without utilization or reset")
    func ignoresMeaninglessWindows() throws {
        let json = """
        {
          "five_hour": { "unexpected": true },
          "seven_day": { "resets_at": null }
        }
        """

        let rows = try ClaudeUsageParser.parseMetricRows(from: Data(json.utf8))
        #expect(rows.isEmpty)
    }
}

import Foundation
import Testing

@testable import Muxy

@Suite("KimiUsageParser")
struct KimiUsageParserTests {
    @Test("parses session and weekly rows from limits with different windows")
    func parseSessionAndWeekly() throws {
        let json = """
        {
          "data": {
            "user": { "membership": { "level": "LEVEL_PRO" } },
            "limits": [
              {
                "window": { "duration": 5, "timeUnit": "HOUR" },
                "detail": { "limit": 200, "used": 50, "resetTime": "2026-04-20T12:00:00Z" }
              },
              {
                "window": { "duration": 7, "timeUnit": "DAY" },
                "detail": { "limit": 1000, "remaining": 400, "resetTime": "2026-04-27T12:00:00Z" }
              }
            ]
          }
        }
        """

        let parsed = try KimiUsageParser.parse(from: Data(json.utf8))

        #expect(parsed.planName == "Pro")
        #expect(parsed.rows.count == 2)
        #expect(parsed.rows[0].label == "Session")
        #expect(parsed.rows[0].percent == 25)
        #expect(parsed.rows[1].label == "Weekly")
        #expect(parsed.rows[1].percent == 60)
    }

    @Test("skips weekly row when identical to session")
    func skipsDuplicateWeekly() throws {
        let json = """
        {
          "data": {
            "limits": [
              { "window": { "duration": 5, "timeUnit": "HOUR" },
                "detail": { "limit": 100, "used": 10, "resetTime": "2026-04-20T12:00:00Z" } }
            ]
          }
        }
        """

        let parsed = try KimiUsageParser.parse(from: Data(json.utf8))
        #expect(parsed.rows.count == 1)
        #expect(parsed.rows[0].label == "Session")
    }
}

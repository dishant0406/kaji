import Foundation
import Testing

@testable import Muxy

@Suite("CodexUsageParser")
struct CodexUsageParserTests {
    @Test("parses wham usage windows and credits")
    func parseWhamUsageWindows() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 6,
              "reset_at": 1738300000,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 24,
              "reset_at": 1738900000,
              "limit_window_seconds": 604800
            }
          },
          "code_review_rate_limit": {
            "primary_window": {
              "used_percent": 12,
              "reset_at": 1738900000,
              "limit_window_seconds": 604800
            }
          },
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": 5.39
          }
        }
        """

        let rows = try CodexUsageParser.parseMetricRows(from: Data(json.utf8))
        #expect(rows.count == 4)
        #expect(rows[0].label == "5h")
        #expect(rows[0].percent == 6)
        #expect(rows[1].label == "7d")
        #expect(rows[2].label == "Reviews")
        #expect(rows[3].label == "Credits")
        #expect(rows[3].detail != nil)
    }

    @Test("reads codex auth from env and file payload")
    func readAuthFromEnvAndFilePayload() throws {
        let envAuth = try CodexUsageProvider.readAuth(env: [
            "CODEX_ACCESS_TOKEN": "token-123",
            "CODEX_ACCOUNT_ID": "acct-1",
        ])
        #expect(envAuth.accessToken == "token-123")
        #expect(envAuth.accountID == "acct-1")
    }
}

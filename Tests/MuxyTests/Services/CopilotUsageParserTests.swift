import Foundation
import Testing

@testable import Muxy

@Suite("CopilotUsageParser")
struct CopilotUsageParserTests {
    @Test("parses paid quota snapshots into rows")
    func parsePaidQuotaSnapshots() throws {
        let json = """
        {
          "copilot_plan": "pro",
          "quota_reset_date": "2025-02-15T00:00:00Z",
          "quota_snapshots": {
            "premium_interactions": {
              "percent_remaining": 80,
              "entitlement": 300,
              "remaining": 240
            },
            "chat": {
              "percent_remaining": 95,
              "entitlement": 1000,
              "remaining": 950
            }
          }
        }
        """

        let rows = try CopilotUsageParser.parseMetricRows(from: Data(json.utf8))
        #expect(rows.count == 2)
        #expect(rows[0].label == "Premium")
        #expect(rows[0].percent == 20)
        #expect(rows[0].detail == "60.0/300")
        #expect(rows[1].label == "Chat")
        #expect(rows[1].percent == 5)
    }

    @Test("parses free tier monthly quotas")
    func parseFreeTierMonthlyQuotas() throws {
        let json = """
        {
          "limited_user_quotas": {
            "chat": 410,
            "completions": 4000
          },
          "monthly_quotas": {
            "chat": 500,
            "completions": 4000
          },
          "limited_user_reset_date": "2025-02-11"
        }
        """

        let rows = try CopilotUsageParser.parseMetricRows(from: Data(json.utf8))
        let rowsByLabel = Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0) })
        #expect(rows.count == 2)
        #expect(rowsByLabel["Chat"]?.percent == 82)
        #expect(rowsByLabel["Completions"]?.percent == 100)
    }

    @Test("extracts token from hosts json")
    func extractTokenFromHostsJSON() throws {
        let json = """
        {
          "github.com": {
            "oauth_token": "ghu_abc"
          }
        }
        """

        let token = try CopilotUsageParser.extractToken(fromHostsData: Data(json.utf8))
        #expect(token == "ghu_abc")
    }

    @Test("extracts token from gh hosts.yml")
    func extractTokenFromGHHostsYAML() {
        let yaml = """
        github.com:
          user: octocat
          oauth_token: ghu_yaml
        another.example.com:
          oauth_token: ghu_other
        """

        let token = CopilotUsageParser.extractToken(fromGHHostsYAML: yaml)
        #expect(token == "ghu_yaml")
    }

    @Test("extracts fallback token from gh hosts.yml when github.com block is absent")
    func extractFallbackTokenFromGHHostsYAML() {
        let yaml = """
        enterprise.internal:
          oauth_token: ghu_enterprise
        """

        let token = CopilotUsageParser.extractToken(fromGHHostsYAML: yaml)
        #expect(token == "ghu_enterprise")
    }
}

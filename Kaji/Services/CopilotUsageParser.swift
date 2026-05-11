import Foundation

enum CopilotUsageParser {
    static func parseMetricRows(from data: Data) throws -> [AIUsageMetricRow] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageParserError.invalidPayload
        }

        var rows: [AIUsageMetricRow] = []

        if let resetDate = AIUsageParserSupport.date(in: payload, keys: ["quota_reset_date", "limited_user_reset_date"]) {
            let monthlyPeriod: TimeInterval = 30 * 24 * 60 * 60

            if let snapshots = payload["quota_snapshots"] as? [String: Any] {
                let orderedKeys = ["premium_interactions", "chat"]
                for rawLabel in orderedKeys {
                    guard let snapshot = snapshots[rawLabel] as? [String: Any] else { continue }
                    let remaining = AIUsageParserSupport.number(in: snapshot, keys: ["remaining"])
                    let limit = AIUsageParserSupport.number(in: snapshot, keys: ["entitlement", "quota", "limit"])
                    let percentRemaining = AIUsageParserSupport.number(in: snapshot, keys: ["percent_remaining"])
                    let percentUsed = percentRemaining.map { max(0, min(100, 100 - $0)) }
                    let detail = AIUsageParserSupport.usageDetail(
                        used: limit.flatMap { total in remaining.map { total - $0 } },
                        limit: limit
                    )
                    rows.append(
                        AIUsageMetricRow(
                            label: displayLabel(for: rawLabel),
                            percent: percentUsed,
                            resetDate: resetDate,
                            detail: detail,
                            periodDuration: monthlyPeriod
                        )
                    )
                }

                for (rawLabel, value) in snapshots where !orderedKeys.contains(rawLabel) {
                    guard let snapshot = value as? [String: Any] else { continue }
                    let remaining = AIUsageParserSupport.number(in: snapshot, keys: ["remaining"])
                    let limit = AIUsageParserSupport.number(in: snapshot, keys: ["entitlement", "quota", "limit"])
                    let percentRemaining = AIUsageParserSupport.number(in: snapshot, keys: ["percent_remaining"])
                    let percentUsed = percentRemaining.map { max(0, min(100, 100 - $0)) }
                    let detail = AIUsageParserSupport.usageDetail(
                        used: limit.flatMap { total in remaining.map { total - $0 } },
                        limit: limit
                    )
                    rows.append(
                        AIUsageMetricRow(
                            label: displayLabel(for: rawLabel),
                            percent: percentUsed,
                            resetDate: resetDate,
                            detail: detail,
                            periodDuration: monthlyPeriod
                        )
                    )
                }
            }

            if let limitedQuotas = payload["monthly_quotas"] as? [String: Any],
               let usedQuotas = payload["limited_user_quotas"] as? [String: Any]
            {
                for (rawLabel, totalValue) in limitedQuotas {
                    guard let total = AIUsageParserSupport.number(in: [rawLabel: totalValue], keys: [rawLabel]) else { continue }
                    let used = AIUsageParserSupport.number(in: usedQuotas, keys: [rawLabel])
                    rows.append(
                        AIUsageMetricRow(
                            label: displayLabel(for: rawLabel),
                            percent: AIUsageParserSupport.utilizationPercent(used: used, limit: total),
                            resetDate: resetDate,
                            detail: AIUsageParserSupport.usageDetail(used: used, limit: total),
                            periodDuration: monthlyPeriod
                        )
                    )
                }
            }
        }

        return rows.filter { $0.percent != nil || $0.resetDate != nil || $0.detail != nil }
    }

    static func extractToken(fromHostsData data: Data) throws -> String? {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageParserError.invalidPayload
        }

        for value in payload.values {
            guard let host = value as? [String: Any] else { continue }
            if let token = AIUsageParserSupport.string(in: host, keys: ["oauth_token", "token", "github_token"]), !token.isEmpty {
                return token
            }
        }

        return nil
    }

    static func extractToken(fromGHHostsYAML yaml: String) -> String? {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        var inGithubBlock = false
        var githubBlockIndent = 0
        var fallbackToken: String?

        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let indent = line.prefix { $0 == " " || $0 == "\t" }.count

            if inGithubBlock, indent <= githubBlockIndent {
                inGithubBlock = false
            }

            if isGithubHostLine(trimmed) {
                inGithubBlock = true
                githubBlockIndent = indent
                continue
            }

            if let token = parseOAuthTokenLine(trimmed) {
                if inGithubBlock {
                    return token
                }
                fallbackToken = fallbackToken ?? token
            }
        }

        return fallbackToken
    }

    private static func parseOAuthTokenLine(_ trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix("oauth_token") else { return nil }
        guard let colonIndex = trimmedLine.firstIndex(of: ":") else { return nil }

        let rawValue = trimmedLine[trimmedLine.index(after: colonIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }

        var token = rawValue
        if (token.hasPrefix("\"") && token.hasSuffix("\"")) || (token.hasPrefix("'") && token.hasSuffix("'")) {
            token = String(token.dropFirst().dropLast())
        }

        return token.isEmpty ? nil : token
    }

    private static func isGithubHostLine(_ trimmedLine: String) -> Bool {
        let normalized = trimmedLine.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: "")
        return normalized == "github.com:"
    }

    private static func displayLabel(for rawLabel: String) -> String {
        switch rawLabel.lowercased() {
        case "premium_interactions":
            "Premium"
        case "chat":
            "Chat"
        case "completions":
            "Completions"
        default:
            rawLabel.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

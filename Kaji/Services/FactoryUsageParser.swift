import Foundation

enum FactoryUsageParserError: Error {
    case invalidPayload
}

enum FactoryUsageParser {
    struct ParsedUsage: Equatable {
        let planName: String?
        let rows: [AIUsageMetricRow]
    }

    static func parse(from data: Data) throws -> ParsedUsage {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = payload["usage"] as? [String: Any]
        else {
            throw FactoryUsageParserError.invalidPayload
        }

        let startDate = date(from: usage, keys: ["startDate", "start_date"])
        let endDate = date(from: usage, keys: ["endDate", "end_date"])
        let periodDuration: TimeInterval? = {
            guard let startDate, let endDate else { return nil }
            return max(0, endDate.timeIntervalSince(startDate))
        }()

        var rows: [AIUsageMetricRow] = []

        if let standard = usage["standard"] as? [String: Any],
           let row = makeRow(
               label: "Standard",
               bucket: standard,
               resetDate: endDate,
               periodDuration: periodDuration
           )
        {
            rows.append(row)
        }

        if let premium = usage["premium"] as? [String: Any],
           let limit = AIUsageParserSupport.number(in: premium, keys: ["totalAllowance", "total_allowance"]),
           limit > 0,
           let row = makeRow(
               label: "Premium",
               bucket: premium,
               resetDate: endDate,
               periodDuration: periodDuration
           )
        {
            rows.append(row)
        }

        let planName: String? = {
            guard let allowance = (usage["standard"] as? [String: Any]).flatMap({
                AIUsageParserSupport.number(in: $0, keys: ["totalAllowance", "total_allowance"])
            })
            else {
                return nil
            }
            if allowance >= 200_000_000 { return "Max" }
            if allowance >= 20_000_000 { return "Pro" }
            if allowance > 0 { return "Basic" }
            return nil
        }()

        return ParsedUsage(planName: planName, rows: rows)
    }

    private static func makeRow(
        label: String,
        bucket: [String: Any],
        resetDate: Date?,
        periodDuration: TimeInterval?
    ) -> AIUsageMetricRow? {
        guard let limit = AIUsageParserSupport.number(in: bucket, keys: ["totalAllowance", "total_allowance"]),
              limit > 0
        else {
            return nil
        }
        let used = AIUsageParserSupport.number(
            in: bucket,
            keys: ["orgTotalTokensUsed", "org_total_tokens_used", "tokensUsed", "tokens_used", "used"]
        ) ?? 0

        let percent = AIUsageParserSupport.utilizationPercent(used: used, limit: limit)
        let detail = "\(AIUsageParserSupport.formatNumber(used)) / \(AIUsageParserSupport.formatNumber(limit)) tokens"
        return AIUsageMetricRow(
            label: label,
            percent: percent,
            resetDate: resetDate,
            detail: detail,
            periodDuration: periodDuration
        )
    }

    private static func date(from dictionary: [String: Any], keys: [String]) -> Date? {
        AIUsageParserSupport.date(in: dictionary, keys: keys)
    }
}

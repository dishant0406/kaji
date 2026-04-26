import Foundation

enum ClaudeUsageParserError: Error {
    case invalidPayload
}

enum ClaudeUsageParser {
    private static let fiveHourDuration: TimeInterval = 5 * 60 * 60
    private static let sevenDayDuration: TimeInterval = 7 * 24 * 60 * 60

    private struct Window {
        let key: String
        let label: String
        let period: TimeInterval
    }

    private static let windowDefinitions: [Window] = [
        Window(key: "five_hour", label: "5h", period: fiveHourDuration),
        Window(key: "seven_day", label: "7d", period: sevenDayDuration),
        Window(key: "seven_day_sonnet", label: "7d Sonnet", period: sevenDayDuration),
        Window(key: "seven_day_omelette", label: "7d Omelette", period: sevenDayDuration),
    ]

    static func parseMetricRows(from data: Data) throws -> [AIUsageMetricRow] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageParserError.invalidPayload
        }

        var rows: [AIUsageMetricRow] = []
        rows.reserveCapacity(windowDefinitions.count + 1)

        for definition in windowDefinitions {
            guard let window = payload[definition.key] as? [String: Any] else { continue }

            let percent = AIUsageParserSupport.number(in: window, keys: ["utilization", "used_percent", "usedPercent"])
                .map { max(0, min(100, $0)) }
            let resetDate = AIUsageParserSupport.date(in: window, keys: ["resets_at", "reset_at", "resetAt", "window_end"])

            guard percent != nil || resetDate != nil else { continue }

            let detail: String? = percent.map { "\(AIUsageParserSupport.formatNumber($0))% used" }
            rows.append(
                AIUsageMetricRow(
                    label: definition.label,
                    percent: percent,
                    resetDate: resetDate,
                    detail: detail,
                    periodDuration: definition.period
                )
            )
        }

        if let extra = payload["extra_usage"] as? [String: Any],
           let used = AIUsageParserSupport.number(in: extra, keys: ["used_credits", "used"])
        {
            let limit = AIUsageParserSupport.number(in: extra, keys: ["monthly_limit", "limit"])
            rows.append(
                AIUsageMetricRow(
                    label: "Credits",
                    percent: nil,
                    resetDate: nil,
                    detail: limit
                        .map { "\(AIUsageParserSupport.currencyDetail(amount: used))/\(AIUsageParserSupport.currencyDetail(amount: $0))" }
                        ?? AIUsageParserSupport.currencyDetail(amount: used)
                )
            )
        }

        return rows
    }
}

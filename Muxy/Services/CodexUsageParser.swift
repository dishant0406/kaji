import Foundation

enum CodexUsageParser {
    private static let windowDefinitions: [AIUsageParserWindowDefinition] = [
        .init(jsonKey: "monthly", label: "Monthly"),
        .init(jsonKey: "daily", label: "Daily"),
        .init(jsonKey: "hourly", label: "Hourly"),
        .init(jsonKey: "current_billing_period", label: "Billing"),
    ]

    static func parseMetricRows(from data: Data) throws -> [AIUsageMetricRow] {
        if let rows = try parseWhamUsageRows(from: data), !rows.isEmpty {
            return rows
        }
        return try AIUsageParserSupport.parseUsageRows(from: data, windowDefinitions: windowDefinitions)
    }

    private static func parseWhamUsageRows(from data: Data) throws -> [AIUsageMetricRow]? {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageParserError.invalidPayload
        }

        guard let rateLimit = payload["rate_limit"] as? [String: Any] else { return nil }

        var rows: [AIUsageMetricRow] = []

        if let primary = rateLimit["primary_window"] as? [String: Any],
           let row = rowForWindow(primary, fallbackLabel: "5h")
        {
            rows.append(row)
        }

        if let secondary = rateLimit["secondary_window"] as? [String: Any],
           let row = rowForWindow(secondary, fallbackLabel: "7d")
        {
            rows.append(row)
        }

        if let reviews = payload["code_review_rate_limit"] as? [String: Any],
           let primary = reviews["primary_window"] as? [String: Any],
           let row = rowForWindow(primary, fallbackLabel: "Reviews")
        {
            rows.append(row)
        }

        if let credits = payload["credits"] as? [String: Any],
           (credits["has_credits"] as? Bool) == true,
           (credits["unlimited"] as? Bool) != true,
           let balance = AIUsageParserSupport.number(in: credits, keys: ["balance"])
        {
            rows.append(
                AIUsageMetricRow(
                    label: "Credits",
                    percent: nil,
                    resetDate: nil,
                    detail: AIUsageParserSupport.currencyDetail(amount: balance)
                )
            )
        }

        return rows
    }

    private static func rowForWindow(_ window: [String: Any], fallbackLabel: String) -> AIUsageMetricRow? {
        let usedPercent = AIUsageParserSupport.number(in: window, keys: ["used_percent"])
        let resetDate = AIUsageParserSupport.date(in: window, keys: ["reset_at"])
        let periodDuration = AIUsageParserSupport.number(in: window, keys: ["limit_window_seconds"]).map { TimeInterval($0) }
        let label = label(for: window, fallback: fallbackLabel)

        guard usedPercent != nil || resetDate != nil else { return nil }

        let detail: String? = if let usedPercent {
            "\(AIUsageParserSupport.formatNumber(usedPercent))% used"
        } else {
            nil
        }

        return AIUsageMetricRow(label: label, percent: usedPercent, resetDate: resetDate, detail: detail, periodDuration: periodDuration)
    }

    private static func label(for window: [String: Any], fallback: String) -> String {
        if let seconds = AIUsageParserSupport.number(in: window, keys: ["limit_window_seconds"]) {
            switch Int(seconds) {
            case 18000: return "5h"
            case 604_800: return fallback == "Reviews" ? "Reviews" : "7d"
            default: return fallback
            }
        }
        return fallback
    }
}

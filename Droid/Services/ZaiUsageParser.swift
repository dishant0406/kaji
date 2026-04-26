import Foundation

enum ZaiUsageParserError: Error {
    case invalidPayload
}

enum ZaiUsageParser {
    static func parseMetricRows(quotaData: Data) throws -> [AIUsageMetricRow] {
        guard let payload = try JSONSerialization.jsonObject(with: quotaData) as? [String: Any] else {
            throw ZaiUsageParserError.invalidPayload
        }

        let limits = extractLimits(from: payload)
        guard !limits.isEmpty else { return [] }

        var rows: [AIUsageMetricRow] = []

        if let session = limit(limits: limits, type: "TOKENS_LIMIT", unit: 3) {
            rows.append(percentRow(label: "Session", from: session, fallbackDuration: 5 * 60 * 60, periodDuration: 5 * 60 * 60))
        }

        if let weekly = limit(limits: limits, type: "TOKENS_LIMIT", unit: 6) {
            rows.append(percentRow(label: "Weekly", from: weekly, fallbackDuration: 7 * 24 * 60 * 60, periodDuration: 7 * 24 * 60 * 60))
        }

        if let searches = limit(limits: limits, type: "TIME_LIMIT", unit: nil) {
            let used = AIUsageParserSupport.number(in: searches, keys: ["currentValue", "current", "used"])
            let total = AIUsageParserSupport.number(in: searches, keys: ["usage", "limit", "max"])
            let reset = AIUsageParserSupport.date(in: searches, keys: ["nextResetTime", "reset_at", "resetAt"]) ?? nextUTCMonthStart()
            rows.append(
                AIUsageMetricRow(
                    label: "Web searches",
                    percent: AIUsageParserSupport.utilizationPercent(used: used, limit: total),
                    resetDate: reset,
                    detail: AIUsageParserSupport.usageDetail(used: used, limit: total),
                    periodDuration: 30 * 24 * 60 * 60
                )
            )
        }

        return rows.filter { $0.percent != nil || $0.detail != nil || $0.resetDate != nil }
    }

    static func parsePlanName(subscriptionData: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: subscriptionData) as? [String: Any] else {
            return nil
        }

        let entries = (payload["data"] as? [[String: Any]]) ?? []
        for entry in entries {
            if let product = AIUsageParserSupport.string(in: entry, keys: ["productName", "product_name", "name"]), !product.isEmpty {
                return product
            }
        }
        return nil
    }

    private static func extractLimits(from payload: [String: Any]) -> [[String: Any]] {
        if let data = payload["data"] as? [String: Any],
           let limits = data["limits"] as? [[String: Any]]
        {
            return limits
        }

        if let limits = payload["limits"] as? [[String: Any]] {
            return limits
        }

        if let rootArray = payload["data"] as? [[String: Any]] {
            return rootArray
        }

        return []
    }

    private static func limit(limits: [[String: Any]], type: String, unit: Int?) -> [String: Any]? {
        for entry in limits {
            guard AIUsageParserSupport.string(in: entry, keys: ["limitType", "type", "name"])?.uppercased() == type else {
                continue
            }

            if let unit {
                guard Int(AIUsageParserSupport.number(in: entry, keys: ["unit"]) ?? -1) == unit else { continue }
            }

            return entry
        }
        return nil
    }

    private static func percentRow(
        label: String,
        from limit: [String: Any],
        fallbackDuration: TimeInterval,
        periodDuration: TimeInterval
    ) -> AIUsageMetricRow {
        let usedPercent = max(0, min(100, AIUsageParserSupport.number(in: limit, keys: ["percentage", "usedPercent", "used_percent"]) ?? 0))
        let reset = AIUsageParserSupport.date(in: limit, keys: ["nextResetTime", "resetAt", "reset_at"]) ?? Date()
            .addingTimeInterval(fallbackDuration)
        return AIUsageMetricRow(
            label: label,
            percent: usedPercent,
            resetDate: reset,
            detail: "\(AIUsageParserSupport.formatNumber(usedPercent))/100",
            periodDuration: periodDuration
        )
    }

    private static func nextUTCMonthStart() -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        var components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0) ?? .current, from: now)
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        if let month = components.month {
            components.month = month + 1
        }
        return calendar.date(from: components) ?? now.addingTimeInterval(30 * 24 * 60 * 60)
    }
}

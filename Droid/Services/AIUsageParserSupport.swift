import Foundation

struct AIUsageParserWindowDefinition {
    let jsonKey: String
    let label: String
}

enum AIUsageParserSupport {
    static func parseUsageRows(
        from data: Data,
        windowDefinitions: [AIUsageParserWindowDefinition]
    ) throws -> [AIUsageMetricRow] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageParserError.invalidPayload
        }

        var rows: [AIUsageMetricRow] = []
        rows.reserveCapacity(windowDefinitions.count)

        for definition in windowDefinitions {
            guard let window = payload[definition.jsonKey] as? [String: Any] else { continue }

            let used = number(in: window, keys: ["used", "usage", "consumed", "current", "spent"])
            let limit = number(in: window, keys: ["limit", "max", "quota", "total", "entitlement"])
            let percent = utilizationPercent(used: used, limit: limit)
            let resetDate = date(
                in: window,
                keys: [
                    "reset_at",
                    "resets_at",
                    "resetAt",
                    "reset",
                    "window_end",
                    "period_end",
                    "end_time",
                    "quota_reset_date",
                    "limited_user_reset_date",
                ]
            )
            let detail = usageDetail(used: used, limit: limit)

            guard percent != nil || resetDate != nil || detail != nil else { continue }

            rows.append(
                AIUsageMetricRow(
                    label: definition.label,
                    percent: percent,
                    resetDate: resetDate,
                    detail: detail
                )
            )
        }

        return rows
    }

    static func number(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            switch value {
            case let number as NSNumber:
                return number.doubleValue
            case let string as String:
                if let parsed = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return parsed
                }
            default:
                continue
            }
        }
        return nil
    }

    static func string(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    static func date(in dictionary: [String: Any], keys: [String]) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]

        let dateOnly = DateFormatter()
        dateOnly.calendar = Calendar(identifier: .iso8601)
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnly.dateFormat = "yyyy-MM-dd"

        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let number = value as? NSNumber {
                return unixDate(from: number.doubleValue)
            }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let seconds = Double(trimmed) {
                    return unixDate(from: seconds)
                }
                if let date = withFraction.date(from: trimmed)
                    ?? withoutFraction.date(from: trimmed)
                    ?? dateOnly.date(from: trimmed)
                {
                    return date
                }
            }
        }
        return nil
    }

    static func unixDate(from value: Double) -> Date {
        value > 10_000_000_000 ? Date(timeIntervalSince1970: value / 1000) : Date(timeIntervalSince1970: value)
    }

    static func utilizationPercent(used: Double?, limit: Double?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        let ratio = used / limit
        return min(max(ratio * 100, 0), 100)
    }

    static func usageDetail(used: Double?, limit: Double?) -> String? {
        guard let used, let limit else { return nil }
        return "\(formatNumber(used))/\(formatNumber(limit))"
    }

    static func formatNumber(_ value: Double) -> String {
        if value >= 100 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    static func currencyDetail(amount: Double, code: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

import Foundation

enum AmpUsageParserError: Error {
    case invalidPayload
    case missingDisplayText
}

enum AmpUsageParser {
    static func parseMetricRows(from data: Data) throws -> [AIUsageMetricRow] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AmpUsageParserError.invalidPayload
        }

        if let ok = payload["ok"] as? Bool, ok == false {
            throw AmpUsageParserError.invalidPayload
        }

        guard let result = payload["result"] as? [String: Any],
              let displayText = AIUsageParserSupport.string(in: result, keys: ["displayText", "display_text"])
        else {
            throw AmpUsageParserError.missingDisplayText
        }

        var rows: [AIUsageMetricRow] = []

        if let balance = parseBalance(from: displayText) {
            let used = max(0, balance.total - balance.remaining)
            rows.append(
                AIUsageMetricRow(
                    label: "Free balance",
                    percent: AIUsageParserSupport.utilizationPercent(used: used, limit: balance.total),
                    resetDate: estimatedResetDate(used: used, hourlyRate: parseHourlyRate(from: displayText)),
                    detail: "\(AIUsageParserSupport.formatNumber(used))/\(AIUsageParserSupport.formatNumber(balance.total))"
                )
            )
        }

        if let credits = parseCredits(from: displayText) {
            rows.append(
                AIUsageMetricRow(
                    label: "Credits",
                    percent: nil,
                    resetDate: nil,
                    detail: AIUsageParserSupport.currencyDetail(amount: credits)
                )
            )
        }

        return rows
    }

    private static func parseBalance(from text: String) -> (remaining: Double, total: Double)? {
        let pattern = #"\$([0-9]+(?:\.[0-9]+)?)\s*/\s*\$([0-9]+(?:\.[0-9]+)?)\s*remaining"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 3,
              let remainingRange = Range(match.range(at: 1), in: text),
              let totalRange = Range(match.range(at: 2), in: text),
              let remaining = Double(text[remainingRange]),
              let total = Double(text[totalRange]),
              total > 0
        else {
            return nil
        }

        return (remaining, total)
    }

    private static func parseHourlyRate(from text: String) -> Double? {
        let pattern = #"\+\$([0-9]+(?:\.[0-9]+)?)\s*/\s*hour"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 2,
              let rateRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Double(text[rateRange])
    }

    private static func parseCredits(from text: String) -> Double? {
        let pattern = #"Individual credits:\s*\$([0-9]+(?:\.[0-9]+)?)\s*remaining"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 2,
              let creditsRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Double(text[creditsRange])
    }

    private static func estimatedResetDate(used: Double, hourlyRate: Double?) -> Date? {
        guard used > 0, let hourlyRate, hourlyRate > 0 else { return nil }
        let hoursUntilReset = used / hourlyRate
        return Date().addingTimeInterval(hoursUntilReset * 60 * 60)
    }
}

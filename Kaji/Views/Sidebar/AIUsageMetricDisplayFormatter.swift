import Foundation

enum AIUsageMetricDisplayFormatter {
    static func paceResult(for row: AIUsageMetricRow, fetchedAt: Date) -> AIUsagePaceResult? {
        guard let percentUsed = row.percent,
              let resetsAt = row.resetDate,
              let duration = row.periodDuration
        else { return nil }

        return AIUsagePaceCalculator.compute(
            usedPercent: percentUsed,
            resetsAt: resetsAt,
            periodDuration: duration,
            now: fetchedAt
        )
    }

    static func paceDetailText(
        for row: AIUsageMetricRow,
        fetchedAt: Date,
        displayMode: AIUsageDisplayMode
    ) -> String? {
        guard let paceResult = paceResult(for: row, fetchedAt: fetchedAt) else { return nil }

        if let eta = paceResult.runsOutIn {
            return "Runs out in \(AIUsagePaceCalculator.formatDuration(eta))"
        }

        if let deficit = paceResult.deficitPercent, deficit > 0 {
            return "\(Int(deficit))% in deficit"
        }

        switch displayMode {
        case .used:
            return "\(Int(paceResult.projectedUsedPercentAtReset))% used at reset"
        case .remaining:
            return "\(Int(paceResult.projectedLeftPercentAtReset))% left at reset"
        }
    }

    static func displayDetail(for row: AIUsageMetricRow, displayMode: AIUsageDisplayMode) -> String? {
        guard let detail = row.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
            return nil
        }

        switch displayMode {
        case .used:
            if let converted = convertRemainingFractionToUsed(detail) {
                return converted
            }
            if let converted = convertRemainingPercentToUsed(detail) {
                return converted
            }
            return detail
        case .remaining:
            if let converted = convertUsedFractionToRemaining(detail) {
                return converted
            }
            if let converted = convertUsedPercentToRemaining(detail) {
                return converted
            }
            return detail
        }
    }

    static func displayPercent(for row: AIUsageMetricRow, displayMode: AIUsageDisplayMode) -> Double? {
        guard let percent = row.percent else { return nil }
        let clamped = max(0, min(100, percent))
        switch displayMode {
        case .used:
            return clamped
        case .remaining:
            return max(0, min(100, 100 - clamped))
        }
    }

    private struct FractionMatch {
        let left: Double
        let total: Double
        let isRemainingLabel: Bool
    }

    private static func convertUsedFractionToRemaining(_ detail: String) -> String? {
        guard let match = fractionMatch(from: detail), !match.isRemainingLabel else { return nil }
        let remaining = max(0, match.total - match.left)
        return "\(AIUsageParserSupport.formatNumber(remaining))/\(AIUsageParserSupport.formatNumber(match.total))"
    }

    private static func convertRemainingFractionToUsed(_ detail: String) -> String? {
        guard let match = fractionMatch(from: detail), match.isRemainingLabel else { return nil }
        let used = max(0, match.total - match.left)
        return "\(AIUsageParserSupport.formatNumber(used))/\(AIUsageParserSupport.formatNumber(match.total))"
    }

    private static func convertUsedPercentToRemaining(_ detail: String) -> String? {
        guard let used = percentMatch(from: detail, modeToken: "used") else { return nil }
        let remaining = max(0, min(100, 100 - used))
        return "\(AIUsageParserSupport.formatNumber(remaining))% left"
    }

    private static func convertRemainingPercentToUsed(_ detail: String) -> String? {
        guard let remaining = percentMatch(from: detail, modeToken: "left|remaining") else { return nil }
        let used = max(0, min(100, 100 - remaining))
        return "\(AIUsageParserSupport.formatNumber(used))% used"
    }

    private static func fractionMatch(from detail: String) -> FractionMatch? {
        let pattern = #"^\s*([0-9]+(?:\.[0-9]+)?)\s*/\s*([0-9]+(?:\.[0-9]+)?)(?:\s*(left|remaining))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(detail.startIndex ..< detail.endIndex, in: detail)
        guard let match = regex.firstMatch(in: detail, options: [], range: range),
              match.numberOfRanges >= 4,
              let leftRange = Range(match.range(at: 1), in: detail),
              let totalRange = Range(match.range(at: 2), in: detail),
              let left = Double(detail[leftRange]),
              let total = Double(detail[totalRange]),
              total > 0
        else {
            return nil
        }

        return FractionMatch(
            left: left,
            total: total,
            isRemainingLabel: match.range(at: 3).location != NSNotFound
        )
    }

    private static func percentMatch(from detail: String, modeToken: String) -> Double? {
        let pattern = "^\\s*([0-9]+(?:\\.[0-9]+)?)%\\s*(?:" + modeToken + ")\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(detail.startIndex ..< detail.endIndex, in: detail)
        guard let match = regex.firstMatch(in: detail, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: detail),
              let value = Double(detail[valueRange])
        else {
            return nil
        }
        return value
    }
}

import Foundation

enum KimiUsageParserError: Error {
    case invalidPayload
}

enum KimiUsageParser {
    struct ParsedUsage: Equatable {
        let planName: String?
        let rows: [AIUsageMetricRow]
    }

    static func parse(from data: Data) throws -> ParsedUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KimiUsageParserError.invalidPayload
        }

        let payload = (root["data"] as? [String: Any]) ?? root

        let planName = extractPlanName(from: payload)
        let limitsArray = payload["limits"] as? [[String: Any]] ?? []

        let candidates = limitsArray.compactMap(parseCandidate(from:))
        let session = candidates.min { ($0.periodMs ?? .greatestFiniteMagnitude) < ($1.periodMs ?? .greatestFiniteMagnitude) }
        let weeklyFromUsage = (payload["usage"] as? [String: Any]).flatMap(parseQuota(from:))

        var rows: [AIUsageMetricRow] = []
        if let session {
            rows.append(row(label: "Session", quota: session.quota, periodMs: session.periodMs))
        }

        let weekly = weeklyFromUsage ?? candidates
            .filter { $0.periodMs != session?.periodMs }
            .max { ($0.periodMs ?? 0) < ($1.periodMs ?? 0) }?
            .quota

        if let weekly, weekly != session?.quota {
            rows.append(row(label: "Weekly", quota: weekly, periodMs: nil))
        }

        return ParsedUsage(planName: planName, rows: rows.filter { $0.percent != nil || $0.resetDate != nil })
    }

    private struct Candidate {
        let quota: Quota
        let periodMs: Double?
    }

    struct Quota: Equatable {
        let used: Double
        let limit: Double
        let resetDate: Date?
    }

    private static func parseCandidate(from item: [String: Any]) -> Candidate? {
        let detail = (item["detail"] as? [String: Any]) ?? item
        guard let quota = parseQuota(from: detail) else { return nil }
        let periodMs = parseWindowPeriodMs(from: item["window"] as? [String: Any])
        return Candidate(quota: quota, periodMs: periodMs)
    }

    private static func parseQuota(from detail: [String: Any]) -> Quota? {
        guard let limit = AIUsageParserSupport.number(in: detail, keys: ["limit", "max", "total"]), limit > 0 else {
            return nil
        }
        let used: Double
        if let direct = AIUsageParserSupport.number(in: detail, keys: ["used", "current"]) {
            used = direct
        } else if let remaining = AIUsageParserSupport.number(in: detail, keys: ["remaining", "remains", "left"]) {
            used = max(0, limit - remaining)
        } else {
            return nil
        }
        let resetDate = AIUsageParserSupport.date(in: detail, keys: ["resetTime", "reset_at", "resetAt", "reset_time"])
        return Quota(used: min(used, limit), limit: limit, resetDate: resetDate)
    }

    private static func row(label: String, quota: Quota, periodMs: Double?) -> AIUsageMetricRow {
        let percent = AIUsageParserSupport.utilizationPercent(used: quota.used, limit: quota.limit)
        let percentLabel = percent.map { "\(AIUsageParserSupport.formatNumber($0))% used" }
        return AIUsageMetricRow(
            label: label,
            percent: percent,
            resetDate: quota.resetDate,
            detail: percentLabel,
            periodDuration: periodMs.map { $0 / 1000 }
        )
    }

    private static func parseWindowPeriodMs(from window: [String: Any]?) -> Double? {
        guard let window,
              let duration = AIUsageParserSupport.number(in: window, keys: ["duration"]),
              duration > 0
        else {
            return nil
        }
        let unit = (AIUsageParserSupport.string(in: window, keys: ["timeUnit", "time_unit"]) ?? "").uppercased()
        if unit.contains("MINUTE") { return duration * 60000 }
        if unit.contains("HOUR") { return duration * 3_600_000 }
        if unit.contains("DAY") { return duration * 86_400_000 }
        if unit.contains("SECOND") { return duration * 1000 }
        return nil
    }

    private static func extractPlanName(from payload: [String: Any]) -> String? {
        guard let user = payload["user"] as? [String: Any],
              let membership = user["membership"] as? [String: Any],
              let raw = AIUsageParserSupport.string(in: membership, keys: ["level", "planName", "plan"]),
              !raw.isEmpty
        else {
            return nil
        }

        var cleaned = raw
        if let range = cleaned.range(of: "LEVEL_", options: .caseInsensitive), range.lowerBound == cleaned.startIndex {
            cleaned.removeSubrange(range)
        }
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        return cleaned.capitalized
    }
}

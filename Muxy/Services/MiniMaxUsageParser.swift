import Foundation

enum MiniMaxUsageParserError: Error {
    case invalidPayload
    case apiError(message: String)
    case authError
}

enum MiniMaxUsageParser {
    private static let codingPlanWindowMs: Double = 5 * 60 * 60 * 1000
    private static let codingPlanWindowToleranceMs: Double = 10 * 60 * 1000
    private static let modelCallsPerPrompt: Double = 15

    private static let globalPromptLimitToPlan: [Int: String] = [
        100: "Starter",
        300: "Plus",
        1000: "Max",
        2000: "Ultra",
    ]

    private static let cnPromptLimitToPlan: [Int: String] = [
        600: "Starter",
        1500: "Plus",
        4500: "Max",
    ]

    static func parseMetricRows(from data: Data) throws -> [AIUsageMetricRow] {
        try parseMetricRows(from: data, region: .global)
    }

    static func parseMetricRows(from data: Data, region: MiniMaxRegion) throws -> [AIUsageMetricRow] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiniMaxUsageParserError.invalidPayload
        }

        let candidatePayloads = payloadCandidates(from: payload)
        for candidate in candidatePayloads {
            try validateAPIStatus(from: candidate)
            if let row = parseModelRemainsRow(from: candidate, rootPayload: payload, region: region) {
                return [row]
            }
        }

        return try AIUsageParserSupport.parseUsageRows(
            from: data,
            windowDefinitions: [
                .init(jsonKey: "monthly", label: "Monthly"),
                .init(jsonKey: "daily", label: "Daily"),
                .init(jsonKey: "requests", label: "Requests"),
            ]
        )
    }

    private static func payloadCandidates(from payload: [String: Any]) -> [[String: Any]] {
        var candidates: [[String: Any]] = [payload]

        if let data = payload["data"] as? [String: Any] {
            candidates.append(data)
            if let result = data["result"] as? [String: Any] {
                candidates.append(result)
            }
        }

        if let result = payload["result"] as? [String: Any] {
            candidates.append(result)
        }

        return candidates
    }

    private static func parseModelRemainsRow(
        from payload: [String: Any],
        rootPayload: [String: Any],
        region: MiniMaxRegion
    ) -> AIUsageMetricRow? {
        guard let remains = modelRemainsArray(in: payload), !remains.isEmpty else { return nil }

        let selectedRow = remains.first { row in
            if let total = AIUsageParserSupport.number(
                in: row,
                keys: ["current_interval_total_count", "currentIntervalTotalCount", "total", "limit"]
            ) {
                return total > 0
            }
            return false
        } ?? remains[0]

        let totalRaw = AIUsageParserSupport.number(
            in: selectedRow,
            keys: ["current_interval_total_count", "currentIntervalTotalCount", "total", "limit"]
        )
        guard let totalRaw, totalRaw > 0 else { return nil }

        let usageFieldCount = AIUsageParserSupport.number(
            in: selectedRow,
            keys: ["current_interval_usage_count", "currentIntervalUsageCount"]
        )

        let remainingCount = AIUsageParserSupport.number(
            in: selectedRow,
            keys: [
                "current_interval_remaining_count", "currentIntervalRemainingCount",
                "current_interval_remains_count", "currentIntervalRemainsCount",
                "current_interval_remain_count", "currentIntervalRemainCount",
                "remaining_count", "remainingCount",
                "remains_count", "remainsCount",
                "remaining", "remains",
                "left_count", "leftCount",
            ]
        )

        let explicitUsed = AIUsageParserSupport.number(
            in: selectedRow,
            keys: ["used_count", "current_interval_used_count", "currentIntervalUsedCount", "used"]
        )

        let inferredRemaining = remainingCount ?? usageFieldCount
        var usedRaw: Double?

        if let explicitUsed {
            usedRaw = explicitUsed
        } else if let inferredRemaining {
            usedRaw = totalRaw - inferredRemaining
        }

        guard var usedRaw else { return nil }
        usedRaw = min(max(usedRaw, 0), totalRaw)

        let resetDate = resetDate(from: selectedRow)

        let explicitPlan = normalizePlanName(
            AIUsageParserSupport.string(
                in: payload,
                keys: ["current_subscribe_title", "plan_name", "plan", "current_plan_title", "combo_title"]
            )
                ?? AIUsageParserSupport.string(
                    in: rootPayload,
                    keys: ["current_subscribe_title", "plan_name", "plan", "current_plan_title", "combo_title"]
                )
                ?? AIUsageParserSupport.string(
                    in: selectedRow,
                    keys: ["current_subscribe_title", "plan_name", "plan"]
                )
        )

        let inferredPlan = inferPlanName(fromLimit: totalRaw, region: region)
        let plan = explicitPlan ?? inferredPlan

        let scale = region == .cn ? (1 / modelCallsPerPrompt) : 1
        let total = round(totalRaw * scale)

        let label = if let plan, !plan.isEmpty {
            "Session (\(plan))"
        } else {
            "Session"
        }

        return AIUsageMetricRow(
            label: label,
            percent: AIUsageParserSupport.utilizationPercent(used: usedRaw * scale, limit: total),
            resetDate: resetDate,
            detail: "\(AIUsageParserSupport.formatNumber(usedRaw * scale))/\(AIUsageParserSupport.formatNumber(total))",
            periodDuration: codingPlanWindowMs / 1000
        )
    }

    private static func modelRemainsArray(in payload: [String: Any]) -> [[String: Any]]? {
        if let value = payload["model_remains"] as? [[String: Any]], !value.isEmpty {
            return value
        }
        if let value = payload["modelRemains"] as? [[String: Any]], !value.isEmpty {
            return value
        }
        return nil
    }

    private static func resetDate(from row: [String: Any]) -> Date? {
        let now = Date()
        let endDate = AIUsageParserSupport.date(in: row, keys: ["end_time", "endTime"])
        if let endDate {
            return endDate
        }

        let remainsRaw = AIUsageParserSupport.number(in: row, keys: ["remains_time", "remainsTime"])
        if let remainsRaw {
            let inferred = inferRemainsIntervalMs(remainsRaw: remainsRaw, endDate: endDate, now: now)
            if inferred > 0 {
                return Date(timeInterval: inferred / 1000, since: now)
            }
        }

        return AIUsageParserSupport.date(in: row, keys: ["reset_at", "resetAt"])
    }

    private static func inferRemainsIntervalMs(remainsRaw: Double, endDate: Date?, now: Date) -> Double {
        guard remainsRaw > 0 else { return 0 }

        let asSecondsMs = remainsRaw * 1000
        let asMillisecondsMs = remainsRaw

        if let endDate {
            let toEndMs = endDate.timeIntervalSince(now) * 1000
            if toEndMs > 0 {
                let secDelta = abs(asSecondsMs - toEndMs)
                let msDelta = abs(asMillisecondsMs - toEndMs)
                return secDelta <= msDelta ? asSecondsMs : asMillisecondsMs
            }
        }

        let maxExpectedMs = codingPlanWindowMs + codingPlanWindowToleranceMs
        let secondsLooksValid = asSecondsMs <= maxExpectedMs
        let millisecondsLooksValid = asMillisecondsMs <= maxExpectedMs

        if secondsLooksValid, !millisecondsLooksValid {
            return asSecondsMs
        }
        if millisecondsLooksValid, !secondsLooksValid {
            return asMillisecondsMs
        }
        if secondsLooksValid, millisecondsLooksValid {
            return asSecondsMs
        }

        let secOverflow = abs(asSecondsMs - maxExpectedMs)
        let msOverflow = abs(asMillisecondsMs - maxExpectedMs)
        return secOverflow <= msOverflow ? asSecondsMs : asMillisecondsMs
    }

    private static func normalizePlanName(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }

        let compact = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let withoutPrefix = compact.replacingOccurrences(
            of: #"(?i)^minimax\s+coding\s+plan\b[:\-]?\s*"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if !withoutPrefix.isEmpty {
            return withoutPrefix
        }

        if compact.range(of: "coding\\s+plan", options: .regularExpression) != nil {
            return "Coding Plan"
        }

        return compact
    }

    private static func inferPlanName(fromLimit totalCount: Double, region: MiniMaxRegion) -> String? {
        guard totalCount > 0 else { return nil }
        let normalized = Int(totalCount.rounded())

        switch region {
        case .cn:
            return cnPromptLimitToPlan[normalized]
        case .global:
            if let direct = globalPromptLimitToPlan[normalized] {
                return direct
            }
            if !normalized.isMultiple(of: Int(modelCallsPerPrompt)) {
                return nil
            }
            return globalPromptLimitToPlan[normalized / Int(modelCallsPerPrompt)]
        }
    }

    private static func validateAPIStatus(from payload: [String: Any]) throws {
        guard let baseResp = payload["base_resp"] as? [String: Any] else { return }

        let statusCode = AIUsageParserSupport.number(in: baseResp, keys: ["status_code", "code"])
        guard let statusCode, Int(statusCode) != 0 else { return }

        let statusMessage = AIUsageParserSupport.string(in: baseResp, keys: ["status_msg", "message"])
            ?? "Unknown error"

        let lowercased = statusMessage.lowercased()
        if Int(statusCode) == 1004
            || lowercased.contains("cookie")
            || lowercased.contains("log in")
            || lowercased.contains("login")
        {
            throw MiniMaxUsageParserError.authError
        }

        throw MiniMaxUsageParserError.apiError(message: statusMessage)
    }
}

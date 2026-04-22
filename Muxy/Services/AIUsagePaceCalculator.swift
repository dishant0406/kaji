import Foundation

enum AIUsagePaceStatus: String {
    case ahead
    case onTrack
    case behind

    var headline: String {
        switch self {
        case .ahead:
            "Plenty of room"
        case .onTrack:
            "Right on target"
        case .behind:
            "Will run out"
        }
    }
}

struct AIUsagePaceResult: Equatable {
    let status: AIUsagePaceStatus
    let projectedUsedPercentAtReset: Double
    let projectedLeftPercentAtReset: Double
    let runsOutIn: TimeInterval?
    let deficitPercent: Double?
}

enum AIUsagePaceCalculator {
    static func compute(
        usedPercent: Double,
        resetsAt: Date,
        periodDuration: TimeInterval,
        now: Date
    ) -> AIUsagePaceResult? {
        let limitPercent: Double = 100

        guard periodDuration > 0 else { return nil }

        let used = max(0, min(limitPercent, usedPercent))
        if used >= limitPercent {
            return AIUsagePaceResult(
                status: .behind,
                projectedUsedPercentAtReset: 100,
                projectedLeftPercentAtReset: 0,
                runsOutIn: nil,
                deficitPercent: nil
            )
        }

        let periodStart = resetsAt.addingTimeInterval(-periodDuration)
        let elapsed = now.timeIntervalSince(periodStart)
        let remaining = resetsAt.timeIntervalSince(now)

        guard elapsed > 0, remaining > 0 else { return nil }

        let elapsedFraction = elapsed / periodDuration
        if elapsedFraction < 0.05 {
            if used == 0 {
                return AIUsagePaceResult(
                    status: .ahead,
                    projectedUsedPercentAtReset: 0,
                    projectedLeftPercentAtReset: 100,
                    runsOutIn: nil,
                    deficitPercent: nil
                )
            }
            return nil
        }

        let usageRate = used / elapsed
        let projectedUsedAtReset = usageRate * periodDuration
        let projectedUsedPercent = max(0, min(100, projectedUsedAtReset))
        let projectedLeftPercent = max(0, min(100, 100 - projectedUsedPercent.rounded()))

        let status: AIUsagePaceStatus = if projectedUsedAtReset <= limitPercent * 0.8 {
            .ahead
        } else if projectedUsedAtReset <= limitPercent {
            .onTrack
        } else {
            .behind
        }

        let expectedUsage = elapsedFraction * limitPercent
        let deficitRaw = used - expectedUsage
        let deficit = deficitRaw > 0 ? deficitRaw : nil

        let runsOutIn: TimeInterval?
        if status == .behind, usageRate > 0 {
            let eta = (limitPercent - used) / usageRate
            if eta > 0, eta < remaining {
                runsOutIn = eta
            } else {
                runsOutIn = nil
            }
        } else {
            runsOutIn = nil
        }

        return AIUsagePaceResult(
            status: status,
            projectedUsedPercentAtReset: max(0, min(100, projectedUsedPercent.rounded())),
            projectedLeftPercentAtReset: projectedLeftPercent,
            runsOutIn: runsOutIn,
            deficitPercent: deficit.map { max(0, min(100, $0.rounded())) }
        )
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval.rounded() / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

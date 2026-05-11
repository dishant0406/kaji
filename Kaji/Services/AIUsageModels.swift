import Foundation

struct AIUsageMetricRow: Identifiable, Equatable {
    let id: String
    let label: String
    let percent: Double?
    let resetDate: Date?
    let detail: String?
    let periodDuration: TimeInterval?

    init(
        label: String,
        percent: Double?,
        resetDate: Date?,
        detail: String?,
        periodDuration: TimeInterval? = nil
    ) {
        id = label
        self.label = label
        self.percent = percent
        self.resetDate = resetDate
        self.detail = detail
        self.periodDuration = periodDuration
    }
}

enum AIProviderUsageState: Equatable {
    case available
    case unavailable(message: String)
    case error(message: String)
}

struct AIProviderUsageSnapshot: Identifiable, Equatable {
    let id: String
    let providerID: String
    let providerName: String
    let providerIconName: String
    let fetchedAt: Date
    let state: AIProviderUsageState
    let rows: [AIUsageMetricRow]

    init(
        providerID: String,
        providerName: String,
        providerIconName: String,
        fetchedAt: Date = Date(),
        state: AIProviderUsageState,
        rows: [AIUsageMetricRow]
    ) {
        id = providerID
        self.providerID = providerID
        self.providerName = providerName
        self.providerIconName = providerIconName
        self.fetchedAt = fetchedAt
        self.state = state
        self.rows = rows
    }
}

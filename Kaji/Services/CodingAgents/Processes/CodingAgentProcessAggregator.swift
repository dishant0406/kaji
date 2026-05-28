import Foundation

enum CodingAgentProcessAggregator {
    static func groups(from matches: [CodingAgentProcessMatch]) -> [CodingAgentProcessProviderGroup] {
        Dictionary(grouping: matches, by: \.providerID)
            .map { _, processes in
                let sorted = processes.sorted { lhs, rhs in
                    if lhs.suspicion != rhs.suspicion { return rank(lhs.suspicion) < rank(rhs.suspicion) }
                    if lhs.process.cpuPercent != rhs.process.cpuPercent { return lhs.process.cpuPercent > rhs.process.cpuPercent }
                    return lhs.process.pid < rhs.process.pid
                }
                let first = sorted[0]
                return CodingAgentProcessProviderGroup(
                    providerID: first.providerID,
                    providerName: first.providerName,
                    iconName: first.providerIconName,
                    processes: sorted
                )
            }
            .sorted { lhs, rhs in
                if lhs.orphanCount != rhs.orphanCount { return lhs.orphanCount > rhs.orphanCount }
                if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
                return lhs.providerName < rhs.providerName
            }
    }

    private static func rank(_ suspicion: CodingAgentProcessSuspicion) -> Int {
        switch suspicion {
        case .orphan: 0
        case .detached: 1
        case .active: 2
        }
    }
}

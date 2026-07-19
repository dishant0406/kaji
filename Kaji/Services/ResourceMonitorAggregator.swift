import Foundation

enum ResourceMonitorAggregator {
    static func buildProjects(
        from readings: [ResourceMonitorTerminalReading],
        orderedProjects: [Project]
    ) -> [ResourceMonitorProjectSnapshot] {
        let grouped = Dictionary(grouping: readings, by: \.descriptor.projectID)

        return orderedProjects.compactMap { project in
            guard let projectReadings = grouped[project.id], !projectReadings.isEmpty else { return nil }

            let terminals = projectReadings
                .map {
                    ResourceMonitorTerminalSnapshot(
                        paneID: $0.descriptor.paneID,
                        tabID: $0.descriptor.tabID,
                        areaID: $0.descriptor.areaID,
                        projectID: $0.descriptor.projectID,
                        title: $0.descriptor.title,
                        processGroupID: $0.processGroupID,
                        pid: $0.pid,
                        processName: $0.processName,
                        ttyName: $0.ttyName,
                        cpuPercent: $0.cpuPercent,
                        memoryBytes: $0.memoryBytes,
                        threadCount: $0.threadCount
                    )
                }
                .sorted { lhs, rhs in
                    let leftCPU = lhs.cpuPercent ?? -1
                    let rightCPU = rhs.cpuPercent ?? -1
                    if leftCPU == rightCPU {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    }
                    return leftCPU > rightCPU
                }

            let processUsages = projectReadings.flatMap(\.processUsages)
            let uniqueUsages = processUsages.reduce(into: [ResourceMonitorProcessIdentity: ResourceMonitorProcessUsage]()) {
                current, usage in
                guard let existing = current[usage.identity] else {
                    current[usage.identity] = usage
                    return
                }
                current[usage.identity] = ResourceMonitorProcessUsage(
                    identity: usage.identity,
                    cpuPercent: max(existing.cpuPercent ?? 0, usage.cpuPercent ?? 0),
                    memoryBytes: max(existing.memoryBytes, usage.memoryBytes)
                )
            }
            let hasProcessUsages = !uniqueUsages.isEmpty

            return ResourceMonitorProjectSnapshot(
                id: project.id,
                name: project.name,
                cpuPercent: hasProcessUsages
                    ? uniqueUsages.values.reduce(0) { $0 + ($1.cpuPercent ?? 0) }
                    : terminals.reduce(0) { $0 + ($1.cpuPercent ?? 0) },
                memoryBytes: hasProcessUsages
                    ? uniqueUsages.values.reduce(0) { $0 + $1.memoryBytes }
                    : terminals.reduce(0) { $0 + ($1.memoryBytes ?? 0) },
                terminals: terminals
            )
        }
    }
}

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

            return ResourceMonitorProjectSnapshot(
                id: project.id,
                name: project.name,
                cpuPercent: terminals.reduce(0) { $0 + ($1.cpuPercent ?? 0) },
                memoryBytes: terminals.reduce(0) { $0 + ($1.memoryBytes ?? 0) },
                terminals: terminals
            )
        }
    }
}

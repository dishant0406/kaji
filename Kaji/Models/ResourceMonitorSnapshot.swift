import Foundation

struct ResourceMonitorTerminalDescriptor: Identifiable, Equatable {
    let paneID: UUID
    let tabID: UUID
    let areaID: UUID
    let projectID: UUID
    let projectName: String
    let title: String

    var id: UUID { paneID }
}

struct ResourceMonitorProcessIdentity: Hashable {
    let pid: Int32
    let startIdentity: ProcessStartIdentity
}

struct ResourceMonitorProcessUsage: Equatable {
    let identity: ResourceMonitorProcessIdentity
    let cpuPercent: Double?
    let memoryBytes: UInt64
}

struct ResourceMonitorTerminalReading: Identifiable, Equatable {
    let descriptor: ResourceMonitorTerminalDescriptor
    let processGroupID: Int32?
    let pid: Int32?
    let processName: String?
    let ttyName: String?
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    let threadCount: Int?
    let processUsages: [ResourceMonitorProcessUsage]

    var id: UUID { descriptor.id }

    init(
        descriptor: ResourceMonitorTerminalDescriptor,
        processGroupID: Int32?,
        pid: Int32?,
        processName: String?,
        ttyName: String?,
        cpuPercent: Double?,
        memoryBytes: UInt64?,
        threadCount: Int?,
        processUsages: [ResourceMonitorProcessUsage] = []
    ) {
        self.descriptor = descriptor
        self.processGroupID = processGroupID
        self.pid = pid
        self.processName = processName
        self.ttyName = ttyName
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.threadCount = threadCount
        self.processUsages = processUsages
    }
}

struct ResourceMonitorTerminalSnapshot: Identifiable, Equatable {
    let paneID: UUID
    let tabID: UUID
    let areaID: UUID
    let projectID: UUID
    let title: String
    let processGroupID: Int32?
    let pid: Int32?
    let processName: String?
    let ttyName: String?
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    let threadCount: Int?

    var id: UUID { paneID }
}

struct ResourceMonitorAppSnapshot: Identifiable, Equatable {
    let id: Int32
    let title: String
    let pid: Int32
    let processName: String
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    let threadCount: Int?
    let terminalDiagnostics: TerminalViewDiagnosticsSnapshot?
}

struct ResourceMonitorProjectSnapshot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let terminals: [ResourceMonitorTerminalSnapshot]
}
